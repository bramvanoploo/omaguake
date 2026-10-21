#!/bin/bash
# Omaguake tmux session launcher and manager
# Ensures persistent terminal sessions across Quickshell restarts with status bar hidden.

set -euo pipefail

SOCKET="omaguake"
SESSION_NAME="${1:-omaguake_tab_1}"
ACTION="${2:-attach}"

# Validate session name: tmux-safe charset only, no leading dash (option injection)
case "$SESSION_NAME" in
  -*|*[!a-zA-Z0-9_.-]*)
    echo "tmux-session: rejecting invalid session name: $SESSION_NAME" >&2
    exit 1
    ;;
esac
case "$ACTION" in
  attach|kill) ;;
  *) ACTION="attach" ;;
esac

# If tmux is not available, fallback to default user shell
if ! command -v tmux >/dev/null 2>&1; then
  SHELL_BIN="${SHELL:-/bin/bash}"
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

# If session does not exist, create it in detached mode and configure options
if ! tmux -L "$SOCKET" has-session -t "$SESSION_NAME" 2>/dev/null; then
  DEFAULT_SHELL="${SHELL:-/bin/bash}"
  tmux -L "$SOCKET" new-session -d -s "$SESSION_NAME" "$DEFAULT_SHELL"
  # Hide status bar completely
  tmux -L "$SOCKET" set-option -t "$SESSION_NAME" status off
  # Set generous history limit
  tmux -L "$SOCKET" set-option -t "$SESSION_NAME" history-limit 10000
  # Avoid escape key delay
  tmux -L "$SOCKET" set-option -t "$SESSION_NAME" escape-time 0
  # Inherit terminal colors
  tmux -L "$SOCKET" set-option -t "$SESSION_NAME" default-terminal "xterm-256color"
fi

# Enable mouse support and clipboard integration across server and session
tmux -L "$SOCKET" set-option -t "$SESSION_NAME" mouse on
tmux -L "$SOCKET" bind-key -T copy-mode MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel "$CLIP_COPY"
tmux -L "$SOCKET" bind-key -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel "$CLIP_COPY"
tmux -L "$SOCKET" bind-key -T copy-mode MouseDown1Pane "select-pane ; send-keys -X cancel"
tmux -L "$SOCKET" bind-key -T copy-mode-vi MouseDown1Pane "select-pane ; send-keys -X cancel"
tmux -L "$SOCKET" bind-key -T copy-mode DoubleClick1Pane "select-pane ; send-keys -X select-word ; send-keys -X copy-pipe-and-cancel $CLIP_COPY"
tmux -L "$SOCKET" bind-key -T copy-mode-vi DoubleClick1Pane "select-pane ; send-keys -X select-word ; send-keys -X copy-pipe-and-cancel $CLIP_COPY"
tmux -L "$SOCKET" bind-key -T copy-mode TripleClick1Pane "select-pane ; send-keys -X select-line ; send-keys -X copy-pipe-and-cancel $CLIP_COPY"
tmux -L "$SOCKET" bind-key -T copy-mode-vi TripleClick1Pane "select-pane ; send-keys -X select-line ; send-keys -X copy-pipe-and-cancel $CLIP_COPY"
tmux -L "$SOCKET" bind-key -T copy-mode C-c send-keys -X copy-pipe-and-cancel "$CLIP_COPY"
tmux -L "$SOCKET" bind-key -T copy-mode-vi C-c send-keys -X copy-pipe-and-cancel "$CLIP_COPY"
tmux -L "$SOCKET" bind-key -T copy-mode Enter send-keys -X copy-pipe-and-cancel "$CLIP_COPY"
tmux -L "$SOCKET" bind-key -T copy-mode-vi Enter send-keys -X copy-pipe-and-cancel "$CLIP_COPY"
tmux -L "$SOCKET" bind-key -T root DoubleClick1Pane "select-pane -t = ; if-shell -F '#{||:#{pane_in_mode},#{mouse_any_flag}}' 'send-keys -M' 'copy-mode -H ; send-keys -X select-word ; send-keys -X copy-pipe-and-cancel $CLIP_COPY'"
tmux -L "$SOCKET" bind-key -T root TripleClick1Pane "select-pane -t = ; if-shell -F '#{||:#{pane_in_mode},#{mouse_any_flag}}' 'send-keys -M' 'copy-mode -H ; send-keys -X select-line ; send-keys -X copy-pipe-and-cancel $CLIP_COPY'"

# Middle-click paste from system clipboard
if [ -n "$CLIP_PASTE" ]; then
  tmux -L "$SOCKET" bind-key -T root MouseDown2Pane run-shell "$CLIP_PASTE 2>/dev/null | tmux load-buffer - ; tmux paste-buffer -p"
  tmux -L "$SOCKET" bind-key -T copy-mode MouseDown2Pane run-shell "tmux send-keys -X cancel ; $CLIP_PASTE 2>/dev/null | tmux load-buffer - ; tmux paste-buffer -p"
  tmux -L "$SOCKET" bind-key -T copy-mode-vi MouseDown2Pane run-shell "tmux send-keys -X cancel ; $CLIP_PASTE 2>/dev/null | tmux load-buffer - ; tmux paste-buffer -p"
fi

# Emit theme OSC color definitions to terminal
if command -v omarchy-theme-osc >/dev/null 2>&1 && [ -f "$HOME/.local/state/omarchy/current/theme/colors.toml" ]; then
  omarchy-theme-osc "$HOME/.local/state/omarchy/current/theme/colors.toml" 2>/dev/null || true
fi

# Attach to the session
exec tmux -L "$SOCKET" attach-session -t "$SESSION_NAME"
