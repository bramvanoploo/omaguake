#!/bin/bash
set -uo pipefail

# 1. Launch floating presentation terminal and block until user closes it
xdg-terminal-exec --app-id=org.omarchy.terminal --title="OmaGuake Setup" -e bash -c '
  source omarchy-restart-gum 2>/dev/null || true
  omarchy-show-logo 2>/dev/null || true
  echo -e "\033[1;34m::\033[0m Installing qmltermwidget dependency..."
  echo -e "\033[0;36m::\033[0m Source: Official repositories (extra)"
  echo
  if command -v yay >/dev/null 2>&1; then
    yay -S --noconfirm qmltermwidget
  else
    sudo pacman -S --noconfirm qmltermwidget
  fi
  echo
  if command -v omarchy-show-done >/dev/null 2>&1; then
    omarchy-show-done
  fi
' || true

# 2. Terminal has now been closed by the user.
# Verify qmltermwidget is installed
if pacman -Q qmltermwidget >/dev/null 2>&1; then
  # Quickshell requires a restart to load newly installed C++ QML modules
  if command -v omarchy-restart-shell >/dev/null 2>&1; then
    omarchy-restart-shell
  fi

  # Wait for Omarchy shell to finish initializing
  for _ in {1..30}; do
    if command -v omarchy-shell >/dev/null 2>&1 && omarchy-shell shell ping >/dev/null 2>&1; then
      break
    fi
    sleep 0.2
  done

  sleep 0.5

  # Automatically show OmaGuake overlay
  if command -v omarchy-shell >/dev/null 2>&1; then
    omarchy-shell shell summon bramvanoploo.omaguake 2>/dev/null || omarchy-shell bramvanoploo.omaguake show 2>/dev/null || true
  fi
else
  # User closed or cancelled installation without installing qmltermwidget
  if command -v omarchy-shell >/dev/null 2>&1; then
    omarchy-shell omaguake.bar resetInstallState 2>/dev/null || true
  fi
fi
