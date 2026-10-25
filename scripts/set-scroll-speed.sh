#!/bin/bash
# Sets OmaGuake tmux scroll speed on the isolated OmaGuake tmux socket.
# Level 1: 1 line per 3 wheel events (minimum / smooth trackpad)
# Level 2: 1 line per 2 wheel events
# Level 3: 1 line per 1 wheel event (normal)
# Level 4: 3 lines per 1 wheel event (fast)
# Level 5: 5 lines per 1 wheel event (maximum / tmux default)

set -euo pipefail

SPEED="${1:-3}"
SOCKET="${2:-${OMAGUAKE_TMUX_SOCKET:-omaguake}}"

# Validate socket name: tmux-safe charset only, no leading dash
case "$SOCKET" in
  ""|-*|*[!a-zA-Z0-9_.-]*)
    echo "set-scroll-speed: rejecting invalid socket name: $SOCKET" >&2
    exit 1
    ;;
esac

# Exit cleanly if tmux is unavailable or no server is running on this socket yet
if ! command -v tmux >/dev/null 2>&1 || ! tmux -L "$SOCKET" list-sessions >/dev/null 2>&1; then
  exit 0
fi

case "$SPEED" in
  1) DIVISOR=3; SCROLL_LINES=1 ;;
  2) DIVISOR=2; SCROLL_LINES=1 ;;
  3) DIVISOR=1; SCROLL_LINES=1 ;;
  4) DIVISOR=1; SCROLL_LINES=3 ;;
  5) DIVISOR=1; SCROLL_LINES=5 ;;
  *) DIVISOR=1; SCROLL_LINES=1 ;;
esac

if [ "$DIVISOR" -gt 1 ]; then
  ROOT_WHEEL_UP="if-shell -F '#{||:#{alternate_on},#{pane_in_mode},#{mouse_any_flag}}' 'send-keys -M' 'set -g @scroll_acc_up 0 ; set -g @scroll_acc_down 0 ; copy-mode -e'"
  COPY_WHEEL_UP="select-pane ; set-option -F @scroll_acc_up \"#{e|+:#{@scroll_acc_up},1}\" ; if-shell -F \"#{==:#{e|%:#{@scroll_acc_up},$DIVISOR},0}\" \"send-keys -X -N 1 scroll-up\""
  COPY_WHEEL_DOWN="select-pane ; set-option -F @scroll_acc_down \"#{e|+:#{@scroll_acc_down},1}\" ; if-shell -F \"#{==:#{e|%:#{@scroll_acc_down},$DIVISOR},0}\" \"send-keys -X -N 1 scroll-down\""
else
  ROOT_WHEEL_UP="if-shell -F '#{||:#{alternate_on},#{pane_in_mode},#{mouse_any_flag}}' 'send-keys -M' 'copy-mode -e'"
  COPY_WHEEL_UP="select-pane ; send-keys -X -N $SCROLL_LINES scroll-up"
  COPY_WHEEL_DOWN="select-pane ; send-keys -X -N $SCROLL_LINES scroll-down"
fi

tmux -L "$SOCKET" \
  set-option -g @scroll_acc_up 0 \; \
  set-option -g @scroll_acc_down 0 \; \
  bind-key -T root WheelUpPane "$ROOT_WHEEL_UP" \; \
  bind-key -T copy-mode WheelUpPane "$COPY_WHEEL_UP" \; \
  bind-key -T copy-mode WheelDownPane "$COPY_WHEEL_DOWN" \; \
  bind-key -T copy-mode-vi WheelUpPane "$COPY_WHEEL_UP" \; \
  bind-key -T copy-mode-vi WheelDownPane "$COPY_WHEEL_DOWN" 2>/dev/null || true
