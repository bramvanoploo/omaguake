#!/bin/bash
# Omaguake tmux session launcher and manager
# Ensures persistent terminal sessions across Quickshell restarts with status bar hidden.

set -e

SOCKET="omaguake"
SESSION_NAME="${1:-omaguake_tab_1}"
ACTION="${2:-attach}"

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

# If session does not exist, create it in detached mode and configure options
if ! tmux -L "$SOCKET" has-session -t "$SESSION_NAME" 2>/dev/null; then
  DEFAULT_SHELL="${SHELL:-/bin/bash}"
  tmux -L "$SOCKET" new-session -d -s "$SESSION_NAME" "$DEFAULT_SHELL"
  # Hide status bar completely
  tmux -L "$SOCKET" set-option -t "$SESSION_NAME" status off
  # Enable mouse support for scrolling & clicking
  tmux -L "$SOCKET" set-option -t "$SESSION_NAME" mouse on
  # Set generous history limit
  tmux -L "$SOCKET" set-option -t "$SESSION_NAME" history-limit 10000
  # Avoid escape key delay
  tmux -L "$SOCKET" set-option -t "$SESSION_NAME" escape-time 0
  # Inherit terminal colors
  tmux -L "$SOCKET" set-option -t "$SESSION_NAME" default-terminal "xterm-256color"
fi

# Attach to the session
exec tmux -L "$SOCKET" attach-session -t "$SESSION_NAME"
