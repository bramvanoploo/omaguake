#!/bin/bash
# Omaguake tmux session launcher and manager
# Ensures persistent terminal sessions across Quickshell restarts with status bar hidden.

set -euo pipefail

SOCKET="omaguake"
SESSION_NAME="${1:-omaguake_tab_1}"
ACTION="${2:-attach}"

# Validate session name: tmux-safe charset only, no leading dash (option injection)
case "$SESSION_NAME" in
  ""|-*|*[!a-zA-Z0-9_.-]*)
    echo "tmux-session: rejecting invalid session name: $SESSION_NAME" >&2
    exit 1
    ;;
esac
case "$ACTION" in
  attach|kill) ;;
  *) ACTION="attach" ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# If tmux is not available, fallback to default user shell (behind the
# OSC 52 relay so TUI clipboard copies still reach the system clipboard)
if ! command -v tmux >/dev/null 2>&1; then
  SHELL_BIN="${SHELL:-/bin/bash}"
  if [ -x "$SCRIPT_DIR/osc52-relay.py" ] && command -v python3 >/dev/null 2>&1; then
    exec "$SCRIPT_DIR/osc52-relay.py" "$SHELL_BIN"
  fi
  exec "$SHELL_BIN"
fi

if [ "$ACTION" = "kill" ]; then
  tmux -L "$SOCKET" kill-session -t "$SESSION_NAME" 2>/dev/null || true
  exit 0
fi

# Ensure terminal capabilities are set
export TERM="${TERM:-xterm-256color}"

# Clipboard tool detection (Wayland / X11)
if command -v wl-copy >/dev/null 2>&1; then
  CLIP_COPY="wl-copy"
elif command -v xclip >/dev/null 2>&1; then
  CLIP_COPY="xclip -selection clipboard"
else
  CLIP_COPY="cat"
fi

if command -v wl-paste >/dev/null 2>&1; then
  CLIP_PASTE="wl-paste -n"
elif command -v xclip >/dev/null 2>&1; then
  CLIP_PASTE="xclip -selection clipboard -o"
else
  CLIP_PASTE=""
fi

# If session does not exist, create it in detached mode and configure options.
# The pane runs through the OSC 52 relay so clipboard escape sequences from
# nested SSH TUIs (e.g. strata) are applied via wl-copy/xclip; qmltermwidget
# and tmux both ignore OSC 52, so the relay is the plugin-side fix.
if ! tmux -L "$SOCKET" has-session -t "$SESSION_NAME" 2>/dev/null; then
  DEFAULT_SHELL="${SHELL:-/bin/bash}"
  PANE_CMD=("$DEFAULT_SHELL")
  if [ -x "$SCRIPT_DIR/osc52-relay.py" ] && command -v python3 >/dev/null 2>&1; then
    export OMAGUAKE_CLIP_COPY="$CLIP_COPY"
    # Security: Copy-to-clipboard support must not grant clipboard-read access.
    # Remote terminal output must not read the local clipboard without an explicit user paste action.
    # Clipboard reads are rejected by default; only export OMAGUAKE_CLIP_PASTE if explicitly enabled.
    if [ "${OMAGUAKE_CLIP_ALLOW_READ:-0}" = "1" ] || [ "${OMAGUAKE_CLIP_ALLOW_READ:-}" = "true" ]; then
      export OMAGUAKE_CLIP_PASTE="$CLIP_PASTE"
    else
      unset OMAGUAKE_CLIP_PASTE 2>/dev/null || true
    fi
    STATE_BASE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/omaguake"
    mkdir -p "$STATE_BASE" && chmod 700 "$STATE_BASE" 2>/dev/null || true
    # State path goes through argv: tmux panes inherit the server env, not
    # this caller's, so a per-pane unique path cannot ride on exported vars.
    PANE_CMD=("$SCRIPT_DIR/osc52-relay.py" --state "$STATE_BASE/pane-state-$SESSION_NAME" "$DEFAULT_SHELL")
  fi
  tmux -L "$SOCKET" \
    new-session -d -s "$SESSION_NAME" "${PANE_CMD[@]}" \; \
    set-option -t "$SESSION_NAME" status off \; \
    set-option -t "$SESSION_NAME" history-limit 10000 \; \
    set-option -t "$SESSION_NAME" escape-time 0 \; \
    set-option -t "$SESSION_NAME" default-terminal "xterm-256color"
fi

# Configure server options, Escape safety, mouse selection, and clipboard integration in one batch
tmux -L "$SOCKET" \
  set-option -t "$SESSION_NAME" mouse on \; \
  set-option -g detach-on-destroy on \; \
  set-option -s escape-time 0 \; \
  set-option -s update-environ "DISPLAY WINDOWID SSH_TTY SSH_CLIENT SSH_ASKPASS HOST HOSTNAME PWD TERM TERM_PROGRAM TERM_PROGRAMS TERMINFO KRB5CCNAME OMAGUAKE_CLIP_COPY" \; \
  unbind-key -q -T root M-Escape \; \
  unbind-key -q -T root Escape \; \
  unbind-key -q -T copy-mode M-Escape \; \
  unbind-key -q -T copy-mode-vi M-Escape \; \
  bind-key -T copy-mode MouseDragEnd1Pane send-keys -X copy-pipe-no-clear "$CLIP_COPY" \; \
  bind-key -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-no-clear "$CLIP_COPY" \; \
  bind-key -T copy-mode MouseDown1Pane "select-pane ; set -g @scroll_acc_up 0 ; set -g @scroll_acc_down 0 ; send-keys -X cancel" \; \
  bind-key -T copy-mode-vi MouseDown1Pane "select-pane ; set -g @scroll_acc_up 0 ; set -g @scroll_acc_down 0 ; send-keys -X cancel" \; \
  bind-key -T copy-mode DoubleClick1Pane "select-pane ; send-keys -X select-word ; send-keys -X copy-pipe-no-clear $CLIP_COPY" \; \
  bind-key -T copy-mode-vi DoubleClick1Pane "select-pane ; send-keys -X select-word ; send-keys -X copy-pipe-no-clear $CLIP_COPY" \; \
  bind-key -T copy-mode TripleClick1Pane "select-pane ; send-keys -X select-line ; send-keys -X copy-pipe-no-clear $CLIP_COPY" \; \
  bind-key -T copy-mode-vi TripleClick1Pane "select-pane ; send-keys -X select-line ; send-keys -X copy-pipe-no-clear $CLIP_COPY" \; \
  bind-key -T copy-mode C-c send-keys -X copy-pipe-and-cancel "$CLIP_COPY" \; \
  bind-key -T copy-mode-vi C-c send-keys -X copy-pipe-and-cancel "$CLIP_COPY" \; \
  bind-key -T copy-mode Enter send-keys -X copy-pipe-and-cancel "$CLIP_COPY" \; \
  bind-key -T copy-mode-vi Enter send-keys -X copy-pipe-and-cancel "$CLIP_COPY" \; \
  bind-key -T root DoubleClick1Pane "select-pane -t = ; if-shell -F '#{||:#{pane_in_mode},#{mouse_any_flag}}' 'send-keys -M' 'copy-mode -H ; send-keys -X select-word ; send-keys -X copy-pipe-no-clear $CLIP_COPY'" \; \
  bind-key -T root TripleClick1Pane "select-pane -t = ; if-shell -F '#{||:#{pane_in_mode},#{mouse_any_flag}}' 'send-keys -M' 'copy-mode -H ; send-keys -X select-line ; send-keys -X copy-pipe-no-clear $CLIP_COPY'" 2>/dev/null || true

# Middle-click paste from system clipboard
if [ -n "$CLIP_PASTE" ]; then
  tmux -L "$SOCKET" \
    bind-key -T root MouseDown2Pane run-shell "$CLIP_PASTE 2>/dev/null | tmux -L $SOCKET load-buffer - ; tmux -L $SOCKET paste-buffer -p" \; \
    bind-key -T copy-mode MouseDown2Pane run-shell "tmux -L $SOCKET send-keys -X cancel ; $CLIP_PASTE 2>/dev/null | tmux -L $SOCKET load-buffer - ; tmux -L $SOCKET paste-buffer -p" \; \
    bind-key -T copy-mode-vi MouseDown2Pane run-shell "tmux -L $SOCKET send-keys -X cancel ; $CLIP_PASTE 2>/dev/null | tmux -L $SOCKET load-buffer - ; tmux -L $SOCKET paste-buffer -p" 2>/dev/null || true
fi

# Configure scroll speed (1=slowest/smooth trackpad, 5=tmux default)
CONFIG_FILE="${HOME:-~}/.config/omarchy/plugins/bramvanoploo.omaguake/settings.json"
if [ ! -f "$CONFIG_FILE" ] && [ -f "$(dirname "$SCRIPT_DIR")/settings.json" ]; then
  CONFIG_FILE="$(dirname "$SCRIPT_DIR")/settings.json"
fi

SCROLL_SPEED=3
if [ -f "$CONFIG_FILE" ]; then
  PARSED_SPEED="$(grep -oE '"scrollSpeed"[[:space:]]*:[[:space:]]*[1-5]' "$CONFIG_FILE" 2>/dev/null | grep -oE '[1-5]$' | head -n 1 || true)"
  if [ -n "$PARSED_SPEED" ]; then
    SCROLL_SPEED="$PARSED_SPEED"
  fi
fi

if [ -x "$SCRIPT_DIR/set-scroll-speed.sh" ]; then
  "$SCRIPT_DIR/set-scroll-speed.sh" "$SCROLL_SPEED" "$SOCKET"
fi

# Emit theme OSC color definitions to terminal
if command -v omarchy-theme-osc >/dev/null 2>&1 && [ -f "${HOME:-~}/.local/state/omarchy/current/theme/colors.toml" ]; then
  omarchy-theme-osc "${HOME:-~}/.local/state/omarchy/current/theme/colors.toml" 2>/dev/null || true
fi

# Attach to the session
exec tmux -L "$SOCKET" attach-session -t "$SESSION_NAME"
