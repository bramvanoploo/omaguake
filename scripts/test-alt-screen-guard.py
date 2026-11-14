#!/usr/bin/env python3
"""Unit tests for AltScreenGuard in osc52-relay.py (unpaired ?1049l fix)."""

import importlib.util
import os
import sys

spec = importlib.util.spec_from_file_location(
    "osc52_relay", os.path.join(os.path.dirname(os.path.abspath(__file__)), "osc52-relay.py")
)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

failures = 0


def run(name, chunks, expected):
    """Feed chunks through one guard, flush at end, compare to expected."""
    global failures
    g = mod.AltScreenGuard()
    out = b"".join(g.feed(c) for c in chunks) + g.feed(b"", flush=True)
    if out != expected:
        failures += 1
        print(f"FAIL {name}\n  in : {chunks}\n  got: {out!r}\n  want:{expected!r}")
    else:
        print(f"ok   {name}")


SAVE = b"\x1b7"

# 1. Unpaired leave (ssh-exit cleanup shape) is dropped.
run(
    "unpaired 1049l dropped",
    [b"Connection to 10.0.0.205 closed.\x1b[?1000l\x1b[?1002l\x1b[?1049l\x1b[?25h"],
    b"Connection to 10.0.0.205 closed.\x1b[?1000l\x1b[?1002l\x1b[?25h",
)

# 2. Paired enter/leave passes through untouched (remote vim :q case).
run(
    "paired cycle untouched",
    [b"\x1b[?1049hvim screen\x1b[?1049l"],
    b"\x1b[?1049hvim screen\x1b[?1049l",
)

# 3. Killed remote vim: enter tracked, first leave paired, second (cleanup) dropped.
run(
    "killed-vim then cleanup",
    [b"\x1b[?1049h", b"alt screen junk", b"\x1b[?1049l\x1b[?1049l"],
    b"\x1b[?1049halt screen junk\x1b[?1049l",
)

# 4. Sequence split across read() boundaries still detected and dropped.
run(
    "split unpaired leave",
    [b"out\x1b[?10", b"49l\x1b[?25h"],
    b"out\x1b[?25h",
)

# 5. Split across a paired enter is still paired (no injection).
run(
    "split paired enter",
    [b"\x1b[?104", b"9hscreen\x1b[?1049l"],
    b"\x1b[?1049hscreen\x1b[?1049l",
)

# 6. OSC payload containing the bytes of a leave is NOT sequence structure.
run(
    "osc payload inert",
    [b"\x1b]0;echo \\x1b[?1049l in title\x07text\x1b[?1049l"],
    b"\x1b]0;echo \\x1b[?1049l in title\x07text",
)

# 7. 47/1047 variants are tracked too (xterm alternate-screen ancestors).
run(
    "1047 pair then unpaired 1049l",
    [b"\x1b[?1047halt\x1b[?1047lthen\x1b[?1049l"],
    b"\x1b[?1047halt\x1b[?1047lthen",
)

# 8. Non-alt mode sequences and long params pass through verbatim.
run(
    "non-alt modes verbatim",
    [b"\x1b[?1000;1002;1006l\x1b[?2004l"],
    b"\x1b[?1000;1002;1006l\x1b[?2004l",
)

# 9. DECSC/DECRC (ESC 7 / ESC 8) untouched.
run(
    "decsc decrc untouched",
    [b"\x1b7\x1b[?1049l\x1b8"],
    SAVE + b"\x1b[?1049l\x1b8",
)

# 10. Nested enters (1049h over 1047h) then single leave: paired.
run(
    "nested enter then leave",
    [b"\x1b[?1047h\x1b[?1049h\x1b[?1049l"],
    b"\x1b[?1047h\x1b[?1049h\x1b[?1049l",
)

# 12. Program's own DECSC before an unpaired leave: its save is the intent.
run(
    "program decsc pins first",
    [b"\x1b7junk\x1b[?1049l"],
    b"\x1b7junk\x1b[?1049l",
)

# 13. DECSC consumed by a DECRC no longer counts as a live save: dropped.
run(
    "decrc consumes the save",
    [b"\x1b7junk\x1b8then\x1b[?1049l"],
    b"\x1b7junk\x1b8then",
)

# 11. Pane death mid-sequence: held bytes are released verbatim at flush.
g = mod.AltScreenGuard()
mid = g.feed(b"data\x1b[?10")
tail = g.feed(b"", flush=True)
assert mid == b"data", mid
assert tail == b"\x1b[?10", tail
print("ok   flush releases partial verbatim")

sys.exit(1 if failures else 0)
