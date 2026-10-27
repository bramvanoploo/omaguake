#!/bin/bash
# End-to-end test: OSC 52 set + query through the relay, inside a PTY.
set -euo pipefail
export WAYLAND_DISPLAY XDG_RUNTIME_DIR
export OMAGUAKE_CLIP_COPY="wl-copy" OMAGUAKE_CLIP_PASTE="wl-paste -n"
cd "$(dirname "$0")/.."
mkdir -p /tmp/opencode

# 1. Test Default Mode: Copy works, Query is REJECTED by default (security).
printf 'INITIAL-SECRET-%s\n' "$(date +%s%N)" | wl-copy

cat > /tmp/opencode/osc52-child.sh <<'EOF'
sleep 0.2
B64=$(printf '{"json":"from-relay"}' | base64 -w0)
printf '\033]52;c;%s\007' "$B64"          # set clipboard
sleep 0.2
printf '\033]52;c;?\007'                   # query clipboard (response -> stdin)
sleep 0.4
line=""
IFS= read -r -t 1 -d $'\a' line || true
printf 'QUERY_GOT:%s\n' "$line" > /tmp/opencode/osc52-query.out
EOF

rm -f /tmp/opencode/osc52-query.out
script -qec 'python3 scripts/osc52-relay.py bash /tmp/opencode/osc52-child.sh' /dev/null >/tmp/opencode/osc52-pty.out 2>&1
sleep 0.2
CLIP_RESULT="$(wl-paste 2>/dev/null || true)"
QUERY_RESULT="$(cat /tmp/opencode/osc52-query.out 2>/dev/null || true)"

echo "=== Default Mode (Secure by Default) ==="
echo "clipboard: $CLIP_RESULT"
echo "query: $QUERY_RESULT"

if [ "$CLIP_RESULT" != '{"json":"from-relay"}' ]; then
  echo "FAIL: Copy did not update clipboard" >&2
  exit 1
fi
if [ "$QUERY_RESULT" != "QUERY_GOT:" ]; then
  echo "FAIL: Query was not rejected by default (unexpected data returned: $QUERY_RESULT)" >&2
  exit 1
fi
echo "PASS: Copy succeeded and read query was safely rejected by default."

# 2. Test Opt-in Mode (--allow-read): Query works when explicitly enabled.
rm -f /tmp/opencode/osc52-query.out
script -qec 'python3 scripts/osc52-relay.py --allow-read bash /tmp/opencode/osc52-child.sh' /dev/null >/tmp/opencode/osc52-pty.out 2>&1
sleep 0.2
OPTIN_QUERY="$(cat /tmp/opencode/osc52-query.out 2>/dev/null || true)"

echo "=== Opt-in Mode (--allow-read) ==="
echo "opt-in query: $(cat -v /tmp/opencode/osc52-query.out 2>/dev/null || true)"
if [[ "$OPTIN_QUERY" != *"eyJqc29uIjoiZnJvbS1yZWxheSJ9"* ]]; then
  echo "FAIL: Opt-in query did not receive expected base64 response" >&2
  exit 1
fi
echo "PASS: Opt-in query succeeded as expected."
