#!/usr/bin/env python3
# OSC 52 relay: runs a shell in a PTY, watches its output for OSC 52
# clipboard sequences (the escape TUIs like strata use for "copy"), applies
# them with the system clipboard tool, and strips them from the stream.
# Everything else passes through untouched, so ssh -> remote TUI copies
# land on the local clipboard even though qmltermwidget/tmux ignore OSC 52.

import base64
import fcntl
import json
import os
import pty
import selectors
import shlex
import signal
import struct
import subprocess
import sys
import time
import tty
import termios

CLI = b"\x1b]52;"  # OSC 52 introducer
B64CHARS = frozenset(
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=?"
)
MAX_PAYLOAD = 1 << 20  # 1 MiB sanity cap per sequence


def echo_ctl_form(data):
    """ECHOCTL mapping the PTY line discipline applies when echoing input:
    control char c (0 < c < 0x20) echoes as '^' + chr(c + 64)."""
    out = bytearray()
    for c in data:
        if 0 < c < 0x20:
            out += bytes((0x5E, c + 64))
        else:
            out.append(c)
    return bytes(out)


def clip_cmds():
    copy = shlex.split(os.environ.get("OMAGUAKE_CLIP_COPY", "wl-copy"))
    paste = shlex.split(os.environ.get("OMAGUAKE_CLIP_PASTE", "wl-paste -n"))
    return copy, paste


def pane_state_path(argv_state=None):
    # Where the relay publishes the pane's real foreground command/cwd so
    # tmux's pane_current_command (which sees the relay, "python3") can be
    # overridden by session-manager.py for the tab title indicators.
    # tmux passes pane commands as argv, so argv wins over env.
    return argv_state or os.environ.get("OMAGUAKE_PANE_STATE")


def fg_info(master):
    """Foreground process group of the inner PTY -> (command, cwd)."""
    try:
        (pgrp,) = struct.unpack("i", fcntl.ioctl(master, termios.TIOCGPGRP, b"\0" * 4))
        with open(f"/proc/{pgrp}/comm", "rb") as f:
            comm = f.read().decode("utf-8", "replace").strip()
        cwd = os.readlink(f"/proc/{pgrp}/cwd")
        if not comm:
            return None
        return comm, cwd
    except (OSError, struct.error):
        return None


def write_state(path, info):
    try:
        d = os.path.dirname(path)
        os.makedirs(d, mode=0o700, exist_ok=True)
        tmp = f"{path}.tmp{os.getpid()}"
        with open(tmp, "w") as f:
            json.dump({"command": info[0], "cwd": info[1]}, f)
        os.chmod(tmp, 0o600)
        os.replace(tmp, path)
    except OSError:
        pass


def filter_osc52(buf):
    """Scan buf for complete OSC 52 sequences.
    Returns (bytes_safe_to_emit, remaining_buffer, events).
    events: (params, payload) for set, (params, None) for clipboard query."""
    out = bytearray()
    events = []
    i = 0
    while True:
        idx = buf.find(CLI, i)
        if idx < 0:
            keep = 0
            for k in range(len(CLI) - 1, 0, -1):
                if buf.endswith(CLI[:k]):
                    keep = k
                    break
            out += buf[i:len(buf) - keep]
            return bytes(out), buf[len(buf) - keep:], events
        out += buf[i:idx]
        # Parameters: printable (no ';' no ESC), terminated by ';'.
        j = k = idx + len(CLI)
        while k < len(buf) and 0x20 <= buf[k] < 0x7F and buf[k] != 0x3B:
            k += 1
        if k >= len(buf) and len(buf) - j < 64:
            return bytes(out), buf[idx:], events  # params incomplete
        if k >= len(buf) or buf[k] != 0x3B:
            out += buf[idx:k]
            i = k
            continue  # not a real OSC 52: emit verbatim
        params = buf[j:k]
        p = e = k + 1
        term = 0
        malformed = False
        while e < len(buf):
            c = buf[e]
            if c == 0x07:
                term = 1
                break
            if c == 0x1B:
                if e + 1 >= len(buf):
                    return bytes(out), buf[idx:], events  # ST incomplete
                if buf[e + 1] == 0x5C:
                    term = 2
                    break
                out += buf[idx:e]
                i = e
                malformed = True
                break
            if chr(c) not in B64CHARS:
                out += buf[idx:e]
                i = e
                malformed = True
                break
            e += 1
        if malformed:
            continue
        if term == 0:
            if e - p > MAX_PAYLOAD:
                out += buf[idx:e]
                i = e
                continue
            return bytes(out), buf[idx:], events  # payload incomplete
        payload = buf[p:e]
        if payload != b"?":
            events.append((params, payload))
        else:
            events.append((params, None))
        i = e + term


def handle_event(params, payload, master, copy_cmd, paste_cmd):
    try:
        if payload is not None:
            data = base64.b64decode(payload)
            if data:
                subprocess.run(copy_cmd, input=data, check=False)
        else:
            try:
                cp = subprocess.run(paste_cmd, capture_output=True, check=False)
            except OSError:
                cp = subprocess.run("true", shell=True, capture_output=True)
            b64 = base64.b64encode(cp.stdout)
            resp = b"\x1b]52;" + params + b";" + b64 + b"\x07"
            # Disable ECHO around the write; the relay also strips the exact
            # response bytes if the PTY echoes them anyway (race/tcsetattr
            # failure), so the response never leaks into the app's output.
            try:
                attrs = termios.tcgetattr(master)
                attrs[3] &= ~termios.ECHO
                termios.tcsetattr(master, termios.TCSANOW, attrs)
                echo_off = True
            except termios.error:
                echo_off = False
            os.write(master, resp)
            if echo_off:
                attrs[3] |= termios.ECHO
                termios.tcsetattr(master, termios.TCSANOW, attrs)
            return resp
    except Exception:
        pass
    return None


def main():
    argv_state = None
    args = sys.argv[1:]
    # Leading options (tmux passes pane commands as per-pane argv):
    while args and args[0] == "--state":
        if len(args) < 2:
            sys.stderr.write("usage: osc52-relay.py --state PATH shell [args...]\n")
            sys.exit(2)
        argv_state = args[1]
        args = args[2:]
    if len(args) < 1:
        sys.stderr.write("usage: osc52-relay.py [--state PATH] shell [args...]\n")
        sys.exit(2)
    argv = args
    copy_cmd, paste_cmd = clip_cmds()

    try:
        winsize = fcntl.ioctl(0, termios.TIOCGWINSZ, b"\0" * 8)
    except OSError:
        winsize = struct.pack("HHHH", 24, 80, 0, 0)

    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, winsize)

    try:
        pid = os.fork()
    except OSError:
        sys.stderr.write("osc52-relay: fork failed\n")
        sys.exit(1)
    if pid == 0:
        os.close(master)
        try:
            os.setsid()
            fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
            for fd in (0, 1, 2):
                os.dup2(slave, fd)
            if slave > 2:
                os.close(slave)
            os.execvp(argv[0], argv)
        except OSError:
            os._exit(127)

    os.close(slave)
    try:
        tty.setraw(0)
    except termios.error:
        pass

    def on_winch(signum, frame):
        try:
            ws = fcntl.ioctl(0, termios.TIOCGWINSZ, b"\0" * 8)
            fcntl.ioctl(master, termios.TIOCSWINSZ, ws)
        except OSError:
            pass

    def forward(signum, frame):
        try:
            os.killpg(pid, signum)
        except OSError:
            pass

    signal.signal(signal.SIGWINCH, on_winch)
    for s in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP, signal.SIGQUIT):
        signal.signal(s, forward)

    sel = selectors.DefaultSelector()
    sel.register(0, selectors.EVENT_READ)
    sel.register(master, selectors.EVENT_READ)

    buf = b""
    pending_echo = b""
    status = 0
    done = False
    state_path = pane_state_path(argv_state)
    last_state = None
    timeout = 1.0
    last_key = 0.0
    while not done:
        for key, _ in sel.select(timeout):
            fd = key.fd
            if fd == 0:
                try:
                    data = os.read(0, 65536)
                except OSError:
                    data = b""
                if data:
                    os.write(master, data)
                    last_key = time.monotonic()
                else:
                    sel.unregister(0)
                continue
            try:
                data = os.read(master, 65536)
            except OSError:
                data = b""
            if not data:
                done = True
                break
            buf += data
            # Drop our own clipboard-query response if the PTY echoed it,
            # in raw form or in the ECHOCTL-mapped form the line discipline
            # produces (control chars echo as '^X').
            if pending_echo:
                for pe in (pending_echo, echo_ctl_form(pending_echo)):
                    if buf.startswith(pe):
                        buf = buf[len(pe):]
                        break
                pending_echo = b""
            out, buf, events = filter_osc52(buf)
            if out:
                os.write(1, out)
            for params, payload in events:
                resp = handle_event(params, payload, master, copy_cmd, paste_cmd)
                if resp:
                    pending_echo = resp
        # Publish the pane's real foreground command/cwd (tmux sees the relay
        # as python3, so session-manager.py reads this file instead). Poll
        # faster right after keypresses so titles update promptly on Enter.
        if state_path:
            info = fg_info(master)
            if info:
                if info != last_state:
                    write_state(state_path, info)
                    last_state = info
                timeout = 0.25 if time.monotonic() - last_key < 2.0 else 1.0
        p, st = os.waitpid(pid, os.WNOHANG)
        if p:
            sel.unregister(master)
            try:
                while True:
                    data = os.read(master, 65536)
                    if not data:
                        break
                    buf += data
            except OSError:
                pass
            # Drain through the filter so a trailing OSC 52 still applies.
            out, buf, events = filter_osc52(buf + b"\0")
            if out:
                os.write(1, out)
            for params, payload in events:
                handle_event(params, payload, master, copy_cmd, paste_cmd)
            done = True
            status = os.WEXITSTATUS(st) if os.WIFEXITED(st) else 128 + os.WTERMSIG(st)

    if state_path:
        try:
            os.unlink(state_path)
        except OSError:
            pass
    if buf:
        os.write(1, buf)
    sys.exit(status)


if __name__ == "__main__":
    main()
