#!/usr/bin/env python3
import sys
import os
import pty
import select
import json
import fcntl
import termios
import struct
import signal

def set_winsize(fd, rows, cols):
    try:
        winsize = struct.pack("HHHH", rows, cols, 0, 0)
        fcntl.ioctl(fd, termios.TIOCSWINSZ, winsize)
    except Exception:
        pass

def main():
    cols = int(sys.argv[1]) if len(sys.argv) > 1 else 100
    rows = int(sys.argv[2]) if len(sys.argv) > 2 else 30
    
    shell = os.environ.get("SHELL", "/bin/bash")
    if not os.path.exists(shell):
        shell = "/bin/bash"

    master, slave = pty.openpty()
    set_winsize(master, rows, cols)

    pid = os.fork()
    if pid == 0:
        # Child process
        os.close(master)
        os.setsid()
        try:
            fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
        except Exception:
            pass
        os.dup2(slave, 0)
        os.dup2(slave, 1)
        os.dup2(slave, 2)
        if slave > 2:
            os.close(slave)
            
        os.environ["TERM"] = "xterm-256color"
        os.environ["COLORTERM"] = "truecolor"
        os.environ["COLUMNS"] = str(cols)
        os.environ["LINES"] = str(rows)
        
        # Execute shell
        try:
            os.execlp(shell, shell)
        except Exception as e:
            sys.stderr.write(f"Failed to start shell {shell}: {e}\n")
            sys.exit(1)

    # Parent process
    os.close(slave)
    
    # Make master non-blocking
    flags = fcntl.fcntl(master, fcntl.F_GETFL)
    fcntl.fcntl(master, fcntl.F_SETFL, flags | os.O_NONBLOCK)

    def cleanup(*args):
        try:
            os.kill(pid, signal.SIGTERM)
        except Exception:
            pass
        sys.exit(0)

    signal.signal(signal.SIGTERM, cleanup)
    signal.signal(signal.SIGHUP, cleanup)
    signal.signal(signal.SIGINT, cleanup)

    stdin_buf = ""

    try:
        while True:
            # Check child status
            res = os.waitpid(pid, os.WNOHANG)
            if res[0] != 0:
                exit_code = os.waitstatus_to_exitcode(res[1]) if hasattr(os, "waitstatus_to_exitcode") else res[1]
                sys.stdout.write(json.dumps({"t": "exit", "code": exit_code}) + "\n")
                sys.stdout.flush()
                break

            r_fds, _, _ = select.select([sys.stdin.fileno(), master], [], [], 0.05)
            
            # Read from master (shell output)
            if master in r_fds:
                try:
                    data = os.read(master, 8192)
                    if data:
                        text = data.decode("utf-8", "replace")
                        sys.stdout.write(json.dumps({"t": "out", "d": text}) + "\n")
                        sys.stdout.flush()
                    else:
                        break
                except (OSError, BlockingIOError):
                    pass

            # Read from stdin (QML input)
            if sys.stdin.fileno() in r_fds:
                line = sys.stdin.readline()
                if not line:
                    break
                stdin_buf += line
                while "\n" in stdin_buf:
                    msg_str, stdin_buf = stdin_buf.split("\n", 1)
                    if not msg_str.strip():
                        continue
                    try:
                        msg = json.loads(msg_str)
                        m_type = msg.get("t")
                        if m_type == "in":
                            text_in = msg.get("d", "")
                            os.write(master, text_in.encode("utf-8"))
                        elif m_type == "resize":
                            c = int(msg.get("cols", cols))
                            r = int(msg.get("rows", rows))
                            set_winsize(master, r, c)
                        elif m_type == "kill":
                            cleanup()
                    except Exception:
                        pass
    finally:
        try:
            os.close(master)
        except Exception:
            pass
        cleanup()

if __name__ == "__main__":
    main()
