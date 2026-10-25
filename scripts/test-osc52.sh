#!/bin/bash
# End-to-end test: OSC 52 set + query through the relay, inside a PTY.
set -u
export WAYLAND_DISPLAY XDG_RUNTIME_DIR
export OMAGUAKE_CLIP_COPY="wl-copy" OMAGUAKE_CLIP_PASTE="wl-paste -n"
cd "$(dirname "$0")/.."
printf 'SENTINEL-%s\n' "$(date +%s%N)" | wl-copy

cat > /tmp/opencode/osc52-child.sh <<'EOF'
sleep 0.4
B64=$(printf '{"json":"from-relay"}' | base64 -w0)
printf '\033]52;c;%s\007' "$B64"          # set clipboard
sleep 0.3
printf '\033]52;c;?\007'                   # query clipboard (response -> stdin)
sleep 0.4
IFS= read -r -t 1 -d $'\a' line
printf 'QUERY_GOT:%s\n' "${line:0:32}" > /tmp/opencode/osc52-query.out
printf '\033]52;c;'                         # incomplete: must NOT touch clipboard
sleep 0.2
printf 'tail-%s\007' 'ZZZ'                  # completes the OSC -> clipboard ZZZ
sleep 0.3
EOF

script -qec 'python3 scripts/osc52-relay.py bash /tmp/opencode/osc52-child.sh' /dev/null >/tmp/opencode/osc52-pty.out 2>&1
sleep 0.3
echo "clipboard: $(wl-paste)"
echo "child out: $(cat /tmp/opencode/osc52-pty.out 2>/dev/null | tr -d '\r')"
echo "query: $(cat /tmp/opencode/osc52-query.out 2>/dev/null)"
