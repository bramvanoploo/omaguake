#!/usr/bin/env python3
"""
Sync Omarchy theme colors, ANSI palette, and opacity to Omaguake dropdown terminal.
Updates QMLTermWidget color schemes and sends OSC escape sequences to active PTY sessions.
"""

import argparse
import glob
import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys

HOME = pathlib.Path.home()
THEME_DIR = HOME / ".local/state/omarchy/current/theme"
THEME_NAME_FILE = HOME / ".local/state/omarchy/current/theme.name"
PROJECT_DIR = pathlib.Path(__file__).resolve().parent.parent
SCHEMES_DIR = PROJECT_DIR / "QMLTermWidget" / "color-schemes"
SETTINGS_FILE = HOME / ".config/omarchy/plugins/bramvanoploo.omaguake/settings.json"
LOCAL_SETTINGS = PROJECT_DIR / "settings.json"
CURRENT_SCHEME_FILE = PROJECT_DIR / "current_scheme.txt"


def hex_to_rgb(hex_code, fallback="188,178,169"):
    if not hex_code:
        return fallback
    h = hex_code.strip().lstrip("#")
    if len(h) != 6:
        return fallback
    try:
        r = int(h[0:2], 16)
        g = int(h[2:4], 16)
        b = int(h[4:6], 16)
        return f"{r},{g},{b}"
    except ValueError:
        return fallback


def parse_colors_toml(path):
    colors = {}
    if not path.is_file():
        return colors
    try:
        for line in path.read_text(encoding="utf-8").splitlines():
            m = re.match(r"^\s*([a-zA-Z0-9_-]+)\s*=\s*[\"']?#?([0-9a-fA-F]{6})", line)
            if m:
                colors[m.group(1)] = m.group(2)
    except Exception as e:
        sys.stderr.write(f"Error reading colors.toml: {e}\n")
    return colors


def parse_foot_ini(path):
    colors = {}
    if not path.is_file():
        return colors
    try:
        for line in path.read_text(encoding="utf-8").splitlines():
            m = re.match(r"^\s*([a-zA-Z0-9_-]+)\s*=\s*#?([0-9a-fA-F]{6})", line)
            if m:
                colors[m.group(1)] = m.group(2)
    except Exception as e:
        sys.stderr.write(f"Error reading foot.ini: {e}\n")
    return colors


def get_current_theme_slug():
    name = "default"
    if THEME_NAME_FILE.is_file():
        try:
            content = THEME_NAME_FILE.read_text(encoding="utf-8").strip()
            if content:
                name = content
        except Exception:
            pass
    slug = re.sub(r"[^a-zA-Z0-9]+", "_", name.lower()).strip("_")
    return slug or "default"


def get_configured_opacity():
    for p in [SETTINGS_FILE, LOCAL_SETTINGS]:
        if p.is_file():
            try:
                data = json.loads(p.read_text(encoding="utf-8"))
                if "overlayOpacityPercent" in data:
                    pct = float(data["overlayOpacityPercent"])
                    return max(0.2, min(1.0, pct / 100.0))
            except Exception:
                pass
    return 0.90


def build_scheme_content(name, opacity, colors_toml, foot_ini):
    bg_hex = foot_ini.get("background") or colors_toml.get("background") or colors_toml.get("bg") or "0c0d13"
    fg_hex = foot_ini.get("foreground") or colors_toml.get("foreground") or colors_toml.get("fg") or "bcb2a9"

    bg_rgb = hex_to_rgb(bg_hex, "12,13,19")
    fg_rgb = hex_to_rgb(fg_hex, "188,178,169")

    bg_intense_hex = colors_toml.get("lighter_bg") or bg_hex
    bg_faint_hex = colors_toml.get("dark_bg") or bg_hex
    bg_intense_rgb = hex_to_rgb(bg_intense_hex, bg_rgb)
    bg_faint_rgb = hex_to_rgb(bg_faint_hex, bg_rgb)

    fg_intense_hex = colors_toml.get("bright_fg") or foot_ini.get("bright7") or fg_hex
    fg_faint_hex = colors_toml.get("muted") or foot_ini.get("bright0") or colors_toml.get("dark_fg") or fg_hex
    fg_intense_rgb = hex_to_rgb(fg_intense_hex, "216,205,196")
    fg_faint_rgb = hex_to_rgb(fg_faint_hex, "67,66,66")

    c_regular = []
    for i in range(8):
        c_hex = foot_ini.get(f"regular{i}") or colors_toml.get(f"color{i}") or "000000"
        c_regular.append(hex_to_rgb(c_hex, bg_rgb if i == 0 else fg_rgb))

    c_bright = []
    for i in range(8):
        c_hex = foot_ini.get(f"bright{i}") or colors_toml.get(f"color{i+8}") or "ffffff"
        c_bright.append(hex_to_rgb(c_hex, fg_intense_rgb))

    lines = [
        "[General]",
        f"Description={name}",
        f"Opacity={opacity:.2f}",
        "",
        "[Background]",
        f"Color={bg_rgb}",
        "",
        "[BackgroundFaint]",
        f"Color={bg_faint_rgb}",
        "",
        "[BackgroundIntense]",
        f"Color={bg_intense_rgb}",
        "",
        "[Foreground]",
        f"Color={fg_rgb}",
        "",
        "[ForegroundFaint]",
        f"Color={fg_faint_rgb}",
        "",
        "[ForegroundIntense]",
        f"Color={fg_intense_rgb}",
        "",
    ]

    for i in range(8):
        lines.extend([
            f"[Color{i}]",
            f"Color={c_regular[i]}",
            "",
            f"[Color{i}Faint]",
            f"Color={c_regular[i]}",
            "",
            f"[Color{i}Intense]",
            f"Color={c_bright[i]}",
            "",
        ])

    return "\n".join(lines).strip() + "\n"


def emit_live_osc_to_ttys(colors_toml):
    """Emit OSC sequences directly to any running PTS terminal attached to quickshell."""
    osc_bytes = b""
    try:
        proc = subprocess.run(
            ["omarchy-theme-osc", str(THEME_DIR / "colors.toml")],
            capture_output=True,
            timeout=2
        )
        if proc.returncode == 0 and proc.stdout:
            osc_bytes = proc.stdout
    except Exception:
        pass

    if not osc_bytes:
        return

    # Find quickshell processes and all descendants
    qs_pids = set()
    for p in glob.glob("/proc/[0-9]*"):
        try:
            with open(p + "/comm", "r", encoding="utf-8", errors="ignore") as f:
                if "quickshell" in f.read():
                    qs_pids.add(int(os.path.basename(p)))
        except Exception:
            pass

    descendants = set(qs_pids)
    changed = True
    while changed:
        changed = False
        for p in glob.glob("/proc/[0-9]*"):
            try:
                with open(p + "/stat", "r", encoding="utf-8", errors="ignore") as f:
                    fields = f.read().split()
                    pid = int(fields[0])
                    ppid = int(fields[3])
                    if ppid in descendants and pid not in descendants:
                        descendants.add(pid)
                        changed = True
            except Exception:
                pass

    # Find ttys attached to quickshell or its descendants
    ttys = set()
    for pid in descendants:
        for fd in glob.glob(f"/proc/{pid}/fd/*"):
            try:
                target = os.readlink(fd)
                if target.startswith("/dev/pts/"):
                    ttys.add(target)
            except Exception:
                pass

    for tty in ttys:
        try:
            with open(tty, "wb", buffering=0) as f:
                f.write(osc_bytes)
        except Exception:
            pass


def main():
    parser = argparse.ArgumentParser(description="Sync Omarchy theme to Omaguake colorscheme")
    parser.add_argument("--opacity", type=float, help="Explicit opacity value (0.0 - 1.0)")
    parser.add_argument("--opacity-percent", type=int, help="Explicit opacity percentage (20 - 100)")
    parser.add_argument("--notify", action="store_true", help="Notify running quickshell via IPC")
    args = parser.parse_args()

    opacity = get_configured_opacity()
    if args.opacity is not None:
        opacity = max(0.2, min(1.0, args.opacity))
    elif args.opacity_percent is not None:
        opacity = max(0.2, min(1.0, args.opacity_percent / 100.0))

    colors_toml = parse_colors_toml(THEME_DIR / "colors.toml")
    foot_ini = parse_foot_ini(THEME_DIR / "foot.ini")
    slug = get_current_theme_slug()

    # Create content hash to bypass Konsole in-memory scheme caching
    raw_key = f"{slug}:{opacity:.2f}:{sorted(colors_toml.items())}:{sorted(foot_ini.items())}"
    h = hashlib.sha256(raw_key.encode("utf-8")).hexdigest()[:8]
    scheme_name = f"Omaguake_{slug}_{h}"

    SCHEMES_DIR.mkdir(parents=True, exist_ok=True)

    # Clean up older Omaguake_*.colorscheme files
    for old_file in SCHEMES_DIR.glob("Omaguake_*.colorscheme"):
        if old_file.name != f"{scheme_name}.colorscheme":
            try:
                old_file.unlink()
            except Exception:
                pass

    # 1. Write theme-specific scheme (e.g. Omaguake_alfa_palette_1a2b3c4d.colorscheme)
    named_content = build_scheme_content(scheme_name, opacity, colors_toml, foot_ini)
    named_file = SCHEMES_DIR / f"{scheme_name}.colorscheme"
    named_file.write_text(named_content, encoding="utf-8")

    # 2. Write base Omaguake.colorscheme as primary fallback
    base_content = build_scheme_content("Omaguake", opacity, colors_toml, foot_ini)
    base_file = SCHEMES_DIR / "Omaguake.colorscheme"
    base_file.write_text(base_content, encoding="utf-8")

    # 3. Save current scheme name for QML
    CURRENT_SCHEME_FILE.write_text(scheme_name, encoding="utf-8")

    # 4. Live recolor running PTS sessions
    emit_live_osc_to_ttys(colors_toml)

    # 5. Notify quickshell via IPC if requested
    if args.notify:
        for tgt in ["omaguake", "bramvanoploo.omaguake"]:
            try:
                subprocess.run(
                    ["omarchy-shell", tgt, "retheme"],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    timeout=1
                )
            except Exception:
                pass

    print(scheme_name)


if __name__ == "__main__":
    main()
