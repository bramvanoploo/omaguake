#!/usr/bin/env bash
# Regenerates preview.png for the OmaGuake banner from preview/template.html.
#
#   ./preview/generate-preview.sh                 # re-render using existing captures
#   ./preview/generate-preview.sh --capture       # re-capture both live screenshots (Wayland session required)
#   ./preview/generate-preview.sh --settings-only # re-capture just the settings panel
#   ./preview/generate-preview.sh --term-only     # re-capture just the terminal overlay
#
# The version pill in the banner is filled from manifest.json ({{VERSION}}).
#
# The live captures drive the running plugin, so the capture phase temporarily
# rewrites the plugin's settings file (in the state dir, see ConfigManager.qml)
# and restores it afterwards. The terminal capture types into the terminal and
# replaces its tmux tabs, so only re-capture it on purpose.
#
# Both captures are change-isolated: one screenshot with the surface closed,
# one with it open, then crop_diff.py takes the bounding box of what changed.
# That follows whatever the theme, opacity, monitor scale or panel alignment
# currently is, instead of guessing at colors or geometry.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_FILE="$PROJECT_DIR/preview.png"
MANIFEST_FILE="$PROJECT_DIR/manifest.json"
TERM_CAPTURE="$SCRIPT_DIR/term_capture.png"
SETTINGS_CAPTURE="$SCRIPT_DIR/settings_capture.png"

MODE="render"
case "${1:-}" in
  --capture)       MODE="capture" ;;
  --settings-only) MODE="settings" ;;
  --term-only)     MODE="term" ;;
  "")              ;;
  *) echo "usage: $0 [--capture | --settings-only | --term-only]" >&2; exit 1 ;;
esac

VERSION=$(python3 -c "import json; print(json.load(open('$MANIFEST_FILE'))['version'])")
PLUGIN_ID=$(python3 -c "import json; print(json.load(open('$MANIFEST_FILE'))['id'])")
echo "==> Omaguake v$VERSION preview banner"

# --- capture phase (shared backup/restore for both captures) -----------------
if [[ "$MODE" != "render" ]]; then
  command -v grim >/dev/null || { echo "grim is required to capture" >&2; exit 1; }
  command -v omarchy-shell >/dev/null || { echo "omarchy-shell is required to capture" >&2; exit 1; }
  [[ "$MODE" == "capture" || "$MODE" == "term" ]] && {
    command -v wtype >/dev/null || { echo "wtype is required to capture the terminal" >&2; exit 1; }
    command -v tmux >/dev/null || { echo "tmux is required to capture the terminal" >&2; exit 1; }
  }
  python3 -c "import PIL" >/dev/null 2>&1 || { echo "python3 Pillow is required to crop" >&2; exit 1; }

  STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/$PLUGIN_ID"
  SETTINGS_FILE="$STATE_DIR/settings.json"
  SETTINGS_BAK="/tmp/omaguake-preview-settings.$$.json"
  SETTINGS_EXISTED=0
  if [[ -f "$SETTINGS_FILE" ]]; then
    cp "$SETTINGS_FILE" "$SETTINGS_BAK"
    SETTINGS_EXISTED=1
  else
    # Empty (not "{}") so restore_settings can tell "there was no file" apart
    # from "there was one" and put the state back exactly as it found it.
    : > "$SETTINGS_BAK"
  fi

  # apply_settings K1=V1 ...: merge values into the live settings file; the
  # plugin watches this file, so the geometry follows immediately. Written via
  # a temp file + rename: a partially written file next to that watcher would
  # read as invalid JSON and reset the runtime settings to defaults.
  apply_settings() {
    python3 - "$SETTINGS_FILE" "$@" <<'PYEOF'
import json, os, sys
path, *pairs = sys.argv[1:]
data = {}
if os.path.exists(path):
    try:
        data = json.load(open(path))
    except Exception:
        data = {}
for p in pairs:
    k, v = p.split("=", 1)
    try:
        data[k] = json.loads(v)
    except Exception:
        data[k] = v
os.makedirs(os.path.dirname(path), exist_ok=True)
tmp = path + ".preview.tmp"
json.dump(data, open(tmp, "w"), indent=2)
os.replace(tmp, path)
PYEOF
  }

  restore_settings() {
    if [[ "$SETTINGS_EXISTED" == "1" ]]; then
      mkdir -p "$STATE_DIR"
      cp "$SETTINGS_BAK" "$SETTINGS_FILE"
    else
      rm -f "$SETTINGS_FILE"
    fi
    rm -f "$SETTINGS_BAK"
  }

  # Banner geometry: 90% of the work area wide, centered, tall enough that the
  # whole settings card fits on screen.
  CAPTURE_WIDTH=90
  CAPTURE_HEIGHT=75

  FRAMES="$(mktemp -d /tmp/omaguake-preview-frames.XXXXXX)"
  cleanup_frames() { rm -rf "$FRAMES"; }
  # Restore on any exit path; signals exit (which runs the EXIT trap) instead
  # of running the handler and falling through into the next capture step.
  trap 'restore_settings; cleanup_frames' EXIT
  trap 'exit 130' INT TERM

  # The frames must be identical apart from the captured surface, so park the
  # panel and the settings popup in the closed state first.
  reset_surfaces() {
    omarchy-shell omaguake.bar closeSettings >/dev/null 2>&1 || true
    omarchy-shell bramvanoploo.omaguake hide  >/dev/null 2>&1 || true
    sleep 2.0
  }
fi

if [[ "$MODE" == "capture" || "$MODE" == "settings" ]]; then
  echo "==> Capturing settings panel"
  reset_surfaces
  grim "$FRAMES/settings_before.png"
  omarchy-shell omaguake.bar openSettings >/dev/null 2>&1 || true
  sleep 1.2
  grim "$FRAMES/settings_after.png"
  omarchy-shell omaguake.bar closeSettings >/dev/null 2>&1 || true
  python3 "$SCRIPT_DIR/crop_diff.py" "$FRAMES/settings_before.png" \
    "$FRAMES/settings_after.png" "$SETTINGS_CAPTURE"
fi

if [[ "$MODE" == "capture" || "$MODE" == "term" ]]; then
  echo "==> Capturing terminal overlay (3 tabs, fastfetch)"
  apply_settings heightPercent="$CAPTURE_HEIGHT" widthPercent="$CAPTURE_WIDTH" \
    panelAlignment='"center"' tabsPosition='"bottom"'
  sleep 1.0
  reset_surfaces
  # Build the session content once, then close and reopen around the frames:
  # sessions live in tmux, so hiding and re-showing restores the same screen.
  tmux -L omaguake list-sessions 2>/dev/null | cut -d: -f1 | grep '^omaguake_tab_' |
    while read -r s; do tmux -L omaguake kill-session -t "$s" 2>/dev/null || true; done
  omarchy-shell bramvanoploo.omaguake show >/dev/null 2>&1 || true
  sleep 0.8
  wtype "cd ~/Projects/omaguake" && wtype -k Return
  sleep 0.3
  wtype "fastfetch" && wtype -k Return
  sleep 1.8
  omarchy-shell bramvanoploo.omaguake newTab >/dev/null 2>&1 || true
  sleep 0.4
  wtype "git status" && wtype -k Return
  sleep 0.6
  omarchy-shell bramvanoploo.omaguake newTab >/dev/null 2>&1 || true
  sleep 0.4
  omarchy-shell bramvanoploo.omaguake selectTab 0 >/dev/null 2>&1 || true
  sleep 0.8
  reset_surfaces
  grim "$FRAMES/term_before.png"
  omarchy-shell bramvanoploo.omaguake show >/dev/null 2>&1 || true
  sleep 1.4
  grim "$FRAMES/term_after.png"
  # Back to a single tab and a hidden panel for the session being used.
  omarchy-shell bramvanoploo.omaguake closeTab 2 >/dev/null 2>&1 || true
  sleep 0.15
  omarchy-shell bramvanoploo.omaguake closeTab 1 >/dev/null 2>&1 || true
  sleep 0.15
  omarchy-shell bramvanoploo.omaguake hide >/dev/null 2>&1 || true
  python3 "$SCRIPT_DIR/crop_diff.py" "$FRAMES/term_before.png" \
    "$FRAMES/term_after.png" "$TERM_CAPTURE" --threshold 30
fi

[[ -f "$TERM_CAPTURE" ]] || { echo "missing $TERM_CAPTURE (run with --capture)" >&2; exit 1; }
[[ -f "$SETTINGS_CAPTURE" ]] || { echo "missing $SETTINGS_CAPTURE (run with --capture)" >&2; exit 1; }

echo "==> Rendering $OUTPUT_FILE"
TMP_HTML="$SCRIPT_DIR/_render.html"
sed "s/{{VERSION}}/$VERSION/g" "$SCRIPT_DIR/template.html" > "$TMP_HTML"
chromium --headless=new --no-sandbox --disable-gpu --hide-scrollbars \
  --force-device-scale-factor=1 --window-size=1920,1080 \
  --screenshot="$OUTPUT_FILE" "file://$TMP_HTML" >/dev/null 2>&1
rm -f "$TMP_HTML"
echo "==> Done: $OUTPUT_FILE"
