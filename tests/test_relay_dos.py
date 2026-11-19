#!/usr/bin/env python3
"""Live-relay denial-of-service sanity check for the OSC 52 relay.

End-to-end counterpart to the unit tests in scripts/: it runs the real
osc52-relay.py in a PTY and feeds it adversarial output through the pane
command, asserting the shapes from the marketplace security review
(unterminated OSC 52 / CSI / DCS streams) stay bounded in time and
memory while every byte is released correctly and alt-screen decisions
still hold.

The pane command writes to its PTY stdout and exits by itself, so the
relay drains, flushes and exits normally. Exit is also verified bounded
when a descendant keeps the PTY slave open (silent or chatty): the
post-shell-exit drain must neither hang nor buffer the stream.

Requires Linux (the relay uses a PTY). Run:  python3 tests/test_relay_dos.py
Exits non-zero on any failure.
"""

import os
import resource
import subprocess
import sys
import tempfile
import time

# Wall-clock cap for "shell exited but a descendant still holds the PTY
# slave" runs: the relay notices shell exit within its 1s poll interval
# and drains for at most EXIT_DRAIN_TIMEOUT (2s); anything past ~3.5s is
# the pre-fix blocking-until-EOF behavior.
EXIT_MAX_SECONDS = 3.5

HERE = os.path.dirname(os.path.abspath(__file__))
RELAY = os.path.join(HERE, "..", "scripts", "osc52-relay.py")

# Python interpreter + relay + sh have non-trivial baselines; only count
# the *delta* against the first (tiny-input) run for the memory bound.
MAX_RSS_KIB = 32 * 1024


def run(name, cmd, expect_out, max_kib=MAX_RSS_KIB):
    before = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss  # KiB
    t0 = time.monotonic()
    p = subprocess.run(
        [sys.executable, RELAY, "sh", "-c", cmd],
        input=b"",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env={"OMAGUAKE_CLIP_COPY": "/bin/true", "PATH": "/usr/bin:/bin"},
        timeout=60,
    )
    dt = time.monotonic() - t0
    rss = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss - before
    ok = p.stdout == expect_out
    print(
        f"{'ok  ' if ok else 'FAIL'} {name}: out {len(p.stdout)}/{len(expect_out)} B, "
        f"{dt:.2f}s, child peak-RSS delta {rss} KiB"
    )
    if not ok:
        print("  got :", p.stdout[:120], b"..." if len(p.stdout) > 120 else "")
        print("  want:", expect_out[:120], b"..." if len(expect_out) > 120 else "")
    return ok and rss <= max_kib


def run_exit(name, cmd, check_out, max_seconds=EXIT_MAX_SECONDS):
    """Shell exits while a descendant keeps the PTY slave open: the relay
    must exit on its own (bounded drain), not block until the descendant
    finishes. check_out receives the full relay stdout."""
    before = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss  # KiB
    t0 = time.monotonic()
    try:
        p = subprocess.run(
            [sys.executable, RELAY, "sh", "-c", cmd],
            input=b"",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env={"OMAGUAKE_CLIP_COPY": "/bin/true", "PATH": "/usr/bin:/bin"},
            timeout=max_seconds + 10,
        )
    except subprocess.TimeoutExpired:
        print(f"FAIL {name}: relay still running after {max_seconds + 10}s (exit hang)")
        return False
    dt = time.monotonic() - t0
    rss = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss - before
    ok = check_out(p.stdout) and dt <= max_seconds and rss <= MAX_RSS_KIB
    print(
        f"{'ok  ' if ok else 'FAIL'} {name}: out {len(p.stdout)} B, {dt:.2f}s, "
        f"child peak-RSS delta {rss} KiB"
    )
    return ok


def main():
    stty = "stty raw 2>/dev/null;"

    ok = run(
        "normal OSC52 copy stripped",
        f"{stty} printf 'copy:\\033]52;c;dGV4dA==\\a\\n'",
        b"copy:\n",
    )
    ok &= run(
        "unpaired 1049l dropped",
        f"{stty} printf 'bye\\033[?1049l'",
        b"bye",
    )

    with tempfile.TemporaryDirectory() as tmp:
        junk = b"A" + b"\x1b]52;c;" + b"A" * 3_000_000 + b"B" * 97 + b"\n"
        f1 = os.path.join(tmp, "unterminated_osc52")
        with open(f1, "wb") as fh:
            fh.write(junk)
        ok &= run("3 MB unterminated OSC52 stream", f"{stty} cat {f1}", junk)

        csi_dcs = (
            b"\x1b[" + b"9" * 3_000_000
            + b"\x1bP" + b"q" * 3_000_000
            + b"\x1b[?1049l\x1b[?25h"
        )
        f2 = os.path.join(tmp, "unterminated_csi_dcs")
        with open(f2, "wb") as fh:
            fh.write(csi_dcs)
        # The trailing unpaired leave still drops even when it follows
        # megabytes of streamed (inert) sequence bodies.
        want = b"\x1b[" + b"9" * 3_000_000 + b"\x1bP" + b"q" * 3_000_000 + b"\x1b[?25h"
        ok &= run(
            "3 MB unterminated CSI+DCS stream, trailing leave dropped",
            f"{stty} cat {f2}",
            want,
        )

    # Bounded post-shell-exit drain: a descendant that inherited the PTY
    # slave must not hang the relay past its own exit. The HUP trap +
    # setsid keeps the descendant alive through the session teardown.
    quiet_desc = (
        f"{stty} printf done; trap '' HUP; "
        "setsid sh -c 'trap \"\" HUP; sleep 6' &"
    )
    ok &= run_exit(
        "silent descendant holding slave: relay exits promptly",
        quiet_desc,
        lambda out: out == b"done",
    )

    # Chatty descendant: chunk interval (0.2s) is below the quiet cap, so
    # the drain runs to the EXIT_DRAIN_TIMEOUT wall-clock cap instead of
    # an idle gap, and the relay exits while the descendant still writes.
    chatty_desc = (
        f"{stty} printf done; trap '' HUP; "
        "setsid sh -c 'trap \"\" HUP; i=0; while [ $i -lt 24 ]; do "
        "dd if=/dev/zero bs=1M count=2 2>/dev/null; sleep 0.2; "
        "i=$((i+1)); done' &"
    )

    def check_chatty(out):
        # Everything the descendant floods after the shell exited is
        # forwarded incrementally (never buffered to EOF): output starts
        # with the shell's own bytes and continues with the flood's NULs.
        return out.startswith(b"done") and set(out[4:]) <= {0}

    ok &= run_exit(
        "flooding descendant after shell exit: streamed, bounded time",
        chatty_desc,
        check_chatty,
    )

    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
