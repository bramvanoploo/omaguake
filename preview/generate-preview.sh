#!/usr/bin/env bash
# Regenerates preview.png for the OmaGuake banner from preview/template.html.
#
#   ./preview/generate-preview.sh            # re-render using existing captures
#   ./preview/generate-preview.sh --capture  # re-capture live screenshots first (Wayland session required)
#
# The version pill in the banner is filled from manifest.json ({{VERSION}}).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_FILE="$PROJECT_DIR/preview.png"
MANIFEST_FILE="$PROJECT_DIR/manifest.json"
TERM_CAPTURE="$SCRIPT_DIR/term_capture.png"
SETTINGS_CAPTURE="$SCRIPT_DIR/settings_capture.png"

CAPTURE=0
[[ "${1:-}" == "--capture" ]] && CAPTURE=1

VERSION=$(python3 -c "import json; print(json.load(open('$MANIFEST_FILE'))['version'])")
echo "==> Omaguake v$VERSION preview banner"

if [[ "$CAPTURE" == "1" ]]; then
  command -v grim >/dev/null || { echo "grim is required to capture" >&2; exit 1; }
  command -v wtype >/dev/null || { echo "wtype is required to capture" >&2; exit 1; }
  command -v omarchy-shell >/dev/null || { echo "omarchy-shell is required to capture" >&2; exit 1; }

  # crop_term IMAGE OUT: crop the terminal overlay by screen geometry
  # (overlay is centered at widthPercent of screen width; the top bar reserved
  # zone offsets its top edge).
  crop_term() {
    python3 - "$1" "$2" <<'PYEOF'
import json, subprocess, sys
from PIL import Image
src, out = sys.argv[1:3]
mon = json.loads(subprocess.run(["hyprctl", "monitors", "-j"],
                                capture_output=True, text=True).stdout)[0]
W, H = mon["width"], mon["height"]
top_off = mon["reserved"][1] * mon["scale"]   # reserved = [left, top, right, bottom]
x0 = round(W * 0.05)          # 90% width, centered (values set for capture)
x1 = W - x0
im = Image.open(src).convert("RGB")
px = im.load()
pred = lambda c: abs(c[0]-12) < 14 and abs(c[1]-21) < 14 and 24 <= c[2] <= 66
x = x0 + 30
run_start = None
for y in range(int(top_off), H):
    if pred(px[x, y]):
        if run_start is None: run_start = y
    elif run_start is not None and y - run_start > 300:
        im.crop((x0 + 2, run_start + 2, x1 - 2, y - 2)).save(out)
        print(f"cropped {x1-x0-4}x{y-run_start-4} at ({x0},{run_start}) -> {out}")
        break
PYEOF
  }

  # crop_panel IMAGE OUT: crop the settings panel by color-key bbox
  crop_panel() {
    python3 - "$1" "$2" <<'PYEOF'
import sys
from PIL import Image
src, out = sys.argv[1:3]
im = Image.open(src).convert("RGB")
W, H = im.size
px = im.load()
pred = lambda c: abs(c[0]-8) < 12 and abs(c[1]-15) < 12 and 20 <= c[2] <= 40

def runs_at_row(y, min_len):
    out, start = [], None
    for x in range(0, W, 2):
        if pred(px[x, y]):
            if start is None: start = x
        else:
            if start is not None and x - start >= min_len: out.append((start, x))
            start = None
    if start is not None and W - start >= min_len: out.append((start, W))
    return out

# left/right: mode of the longest content-row run across many rows
cands = []
for y in range(H // 3, 2 * H // 3, 40):
    r = runs_at_row(y, W // 4)
    if r:
        best = max(r, key=lambda t: t[1] - t[0])
        cands.append(best)
left = max(min(a for a, _ in cands), 0)
right = min(max(b for _, b in cands), W)
# top/bottom: longest run in a column just inside the left edge
ys, start = [], None
x = left + 28
for y in range(H):
    if pred(px[x, y]):
        if start is None: start = y
    else:
        if start is not None and y - start >= H // 4: ys.append((start, y))
        start = None
if start is not None and H - start >= H // 4: ys.append((start, H))
top, bottom = max(ys, key=lambda t: t[1] - t[0])
Image.open(src).crop((left, top, right, bottom)).save(out)
print(f"cropped {right-left}x{bottom-top} -> {out}")
PYEOF
  }

  echo "==> Capturing settings panel"
  omarchy-shell omaguake.bar openSettings >/dev/null 2>&1 || true
  sleep 1.2
  grim /tmp/_omaguake_settings_full.png
  omarchy-shell omaguake.bar closeSettings >/dev/null 2>&1 || true
  crop_panel /tmp/_omaguake_settings_full.png "$SETTINGS_CAPTURE"
  rm -f /tmp/_omaguake_settings_full.png

  echo "==> Capturing terminal overlay (3 tabs, fastfetch)"
  SETTINGS_BAK=/tmp/_omaguake_settings.json.bak
  cp "$PROJECT_DIR/settings.json" "$SETTINGS_BAK"
  python3 - "$PROJECT_DIR/settings.json" <<'PYEOF'
import json, sys
p = sys.argv[1]
s = json.load(open(p))
s["widthPercent"], s["heightPercent"] = 90, 75
json.dump(s, open(p, "w"), indent=2)
PYEOF
  sleep 1.0
  omarchy-shell bramvanoploo.omaguake hide >/dev/null 2>&1 || true
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
  grim /tmp/_omaguake_term_full.png
  omarchy-shell bramvanoploo.omaguake closeTab 2 >/dev/null 2>&1 || true
  sleep 0.15
  omarchy-shell bramvanoploo.omaguake closeTab 1 >/dev/null 2>&1 || true
  sleep 0.15
  omarchy-shell bramvanoploo.omaguake hide >/dev/null 2>&1 || true
  cp "$SETTINGS_BAK" "$PROJECT_DIR/settings.json"
  crop_term /tmp/_omaguake_term_full.png "$TERM_CAPTURE"
  rm -f /tmp/_omaguake_term_full.png
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
