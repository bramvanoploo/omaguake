# Tests

Run from the repository root:

| File | What it covers | How |
|---|---|---|
| `scripts/test_osc52_relay.py` | OSC 52 relay security: `Osc52Filter` incremental scanning (equivalence with one-shot, ST split across reads, bounded holds under adversarial streams), `clip_cmds`, `handle_event` caps and rate limits | `python3 -m unittest discover -s scripts -p 'test_*.py'` or `python3 -m unittest test_osc52_relay` (run from `scripts/`) |
| `scripts/test-alt-screen-guard.py` | Alt-screen guard: unpaired-leave dropping, split sequences, DECSC/DECRC, bounded holds + verbatim streaming for oversized/unterminated CSI and string sequences | `python3 scripts/test-alt-screen-guard.py` |
| `scripts/test-osc52.sh` | Live tmux/relay behavior: OSC 52 copy passthrough and opt-in (`--allow-read`) clipboard query | `bash scripts/test-osc52.sh` |
| `tests/test_relay_dos.py` | Live-relay denial-of-service sanity: 3 MB unterminated OSC 52 / CSI / DCS streams stay bounded in time and RSS, output byte-exact, unpaired alt-screen leave after the streams still dropped; post-shell-exit drain stays bounded (quiet gap / wall-clock cap) when a descendant holds the PTY slave, silent or flooding (Linux only) | `python3 tests/test_relay_dos.py` |
