#!/usr/bin/env python3
"""
Sync Omarchy theme colors and opacity to Omaguake QMLTermWidget colorscheme.
"""

import argparse
import json
import os
import pathlib
import re
import subprocess
import sys

HOME = pathlib.Path.home()
THEME_DIR = HOME / ".local/state/omarchy/current/theme"
PROJECT_DIR = pathlib.Path("/home/bram/Projects/omaguake")
SETTINGS_FILE = HOME / ".config/omarchy/plugins/bramvanoploo.omaguake/settings.json"
LOCAL_SETTINGS = PROJECT_DIR / "settings.json"


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

    # Background & Foreground
    bg_hex = foot_ini.get("background") or colors_toml.get("background") or colors_toml.get("bg") or "0c0d13"
    fg_hex = foot_ini.get("foreground") or colors_toml.get("foreground") or colors_toml.get("fg") or "bcb2a9"

    bg_rgb = hex_to_rgb(bg_hex, "12,13,19")
    fg_rgb = hex_to_rgb(fg_hex, "188,178,169")

    # Background shades
    bg_intense_hex = colors_toml.get("lighter_bg") or bg_hex
    bg_faint_hex = colors_toml.get("dark_bg") or bg_hex
    bg_intense_rgb = hex_to_rgb(bg_intense_hex, bg_rgb)
    bg_faint_rgb = hex_to_rgb(bg_faint_hex, bg_rgb)

    # Foreground shades
    fg_intense_hex = colors_toml.get("bright_fg") or foot_ini.get("bright7") or fg_hex
    fg_faint_hex = colors_toml.get("muted") or foot_ini.get("bright0") or colors_toml.get("dark_fg") or fg_hex
    fg_intense_rgb = hex_to_rgb(fg_intense_hex, "216,205,196")
    fg_faint_rgb = hex_to_rgb(fg_faint_hex, "67,66,66")

    # ANSI 0-7 (Regular)
    c_regular = []
    for i in range(8):
        c_hex = foot_ini.get(f"regular{i}") or colors_toml.get(f"color{i}") or "000000"
        c_regular.append(hex_to_rgb(c_hex, bg_rgb if i == 0 else fg_rgb))

    # ANSI 8-15 (Intense / Bright)
    c_bright = []
    for i in range(8):
        c_hex = foot_ini.get(f"bright{i}") or colors_toml.get(f"color{i+8}") or "ffffff"
        c_bright.append(hex_to_rgb(c_hex, fg_intense_rgb))

    scheme_lines = [
        "[General]",
        "Description=Omaguake",
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
        scheme_lines.extend([
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

    scheme_content = "\n".join(scheme_lines).strip() + "\n"

    # Targets to write
    target_paths = [
        PROJECT_DIR / "QMLTermWidget" / "color-schemes" / "Omaguake.colorscheme",
        HOME / ".local" / "lib" / "qt6" / "qml" / "QMLTermWidget" / "color-schemes" / "Omaguake.colorscheme",
    ]

    for target in target_paths:
        try:
            target.parent.mkdir(parents=True, exist_ok=True)
            # If target is a symlink pointing to another target, just write once
            if target.is_symlink() and target.resolve() == target_paths[0].resolve() and target != target_paths[0]:
                continue
            target.write_text(scheme_content, encoding="utf-8")
        except Exception as e:
            sys.stderr.write(f"Failed to write {target}: {e}\n")

    if args.notify:
        for tgt in ["omaguake", "bramvanoploo.omaguake"]:
            try:
                subprocess.run(
                    ["quickshell", "ipc", "-p", "/usr/share/omarchy/shell", "call", tgt, "retheme"],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    timeout=1
                )
            except Exception:
                pass


if __name__ == "__main__":
    main()
