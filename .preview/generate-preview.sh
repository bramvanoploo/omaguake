#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_FILE="$PROJECT_DIR/preview.png"
MANIFEST_FILE="$PROJECT_DIR/manifest.json"

CAPTURE_NEW=0
if [[ "${1:-}" == "--capture" ]]; then
  CAPTURE_NEW=1
fi

# Ensure manifest exists
if [[ ! -f "$MANIFEST_FILE" ]]; then
  echo "Error: manifest.json not found at $MANIFEST_FILE" >&2
  exit 1
fi

VERSION=$(python3 -c "import json; print(json.load(open('$MANIFEST_FILE'))['version'])" 2>/dev/null || echo "0.8.1")
echo "==> Preparing preview banner for Omaguake v$VERSION"

# Capture live screenshots if requested or missing
if (( CAPTURE_NEW )) || [[ ! -f "$SCRIPT_DIR/term_capture.png" ]] || [[ ! -f "$SCRIPT_DIR/settings_capture.png" ]]; then
  echo "==> Capturing live assets via Wayland (grim & omarchy-shell)..."
  
  if ! command -v grim >/dev/null 2>&1 || ! command -v omarchy-shell >/dev/null 2>&1; then
    echo "Warning: grim or omarchy-shell not available. Using existing component images." >&2
  else
    # 1. Capture settings panel
    omarchy-shell omaguake.bar openSettings || true
    sleep 0.8
    grim /tmp/_full_settings.png
    omarchy-shell omaguake.bar closeSettings || true
    magick /tmp/_full_settings.png -crop 784x915+1942+48 +repage "$SCRIPT_DIR/settings_capture.png"
    rm -f /tmp/_full_settings.png

    # 2. Capture terminal overlay with 3 tabs and fastfetch
    omarchy-shell bramvanoploo.omaguake show || true
    sleep 0.7
    wtype "clear" && wtype -k Return || true
    sleep 0.2
    wtype "fastfetch" && wtype -k Return || true
    sleep 0.8
    omarchy-shell bramvanoploo.omaguake newTab || true
    sleep 0.3
    wtype "git status" && wtype -k Return || true
    sleep 0.4
    omarchy-shell bramvanoploo.omaguake newTab || true
    sleep 0.3
    omarchy-shell bramvanoploo.omaguake selectTab 0 || true
    sleep 0.5
    grim -g "0,26 2880x900" /tmp/_full_term.png

    # Clean up tabs
    omarchy-shell bramvanoploo.omaguake closeTab 2 || true
    sleep 0.1
    omarchy-shell bramvanoploo.omaguake closeTab 1 || true
    sleep 0.1
    omarchy-shell bramvanoploo.omaguake hide || true

    magick /tmp/_full_term.png -crop 1600x900+0+0 +repage -resize 1400x "$SCRIPT_DIR/term_capture.png"
    rm -f /tmp/_full_term.png
  fi
fi

# Verify component images exist
if [[ ! -f "$SCRIPT_DIR/term_capture.png" ]] || [[ ! -f "$SCRIPT_DIR/settings_capture.png" ]]; then
  echo "Error: Required asset images missing in $SCRIPT_DIR" >&2
  exit 1
fi

# Generate index.html from template
RENDER_HTML="$SCRIPT_DIR/index.html"
sed "s/{{VERSION}}/$VERSION/g" "$SCRIPT_DIR/template.html" > "$RENDER_HTML"

echo "==> Rendering 1920x1080 preview banner via Chromium headless..."
chromium \
  --headless \
  --no-sandbox \
  --disable-gpu \
  --screenshot="$OUTPUT_FILE" \
  --window-size=1920,1080 \
  "file://$RENDER_HTML"

rm -f "$RENDER_HTML"

if command -v identify >/dev/null 2>&1; then
  identify "$OUTPUT_FILE"
fi

echo "==> Successfully created $OUTPUT_FILE for v$VERSION!"
