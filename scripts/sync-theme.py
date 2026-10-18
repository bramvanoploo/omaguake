#!/usr/bin/env python3
"""
Sync Omarchy theme colors and ANSI palette to OmaGuake dropdown terminal.
Emits OSC escape sequences directly to active OmaGuake tmux client and pane PTYs.
"""

import argparse
import os
import pathlib
import re
import subprocess
import sys

HOME = pathlib.Path.home()
THEME_DIR = HOME / ".local/state/omarchy/current/theme"
THEME_NAME_FILE = HOME / ".local/state/omarchy/current/theme.name"


def parse_colors_toml(path):
    colors = {}
    if not path.is_file():
        return colors
    try:
        for line in path.read_text(encoding="utf-8").splitlines():
            m = re.match(r"^\s*([a-zA-Z0-9_-]+)\s*=\s*[\"']?#?([0-9a-fA-F]{6})", line)
            if m:
                colors[m.group(1)] = f"#{m.group(2)}"
    except Exception as e:
        sys.stderr.write(f"Error reading colors.toml: {e}\n")
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


def build_osc_bytes():
    """Obtain OSC palette escape sequences via omarchy-theme-osc or fallback parser."""
    colors_toml_path = THEME_DIR / "colors.toml"
    try:
        proc = subprocess.run(
            ["omarchy-theme-osc", str(colors_toml_path)],
            capture_output=True,
            timeout=1.5,
        )
        if proc.returncode == 0 and proc.stdout:
            return proc.stdout
    except Exception:
        pass

    colors = parse_colors_toml(colors_toml_path)
    if not colors:
        return b""

    parts = []
    osc_map = [
        (10, "foreground"),
        (11, "background"),
        (12, "cursor"),
        (17, "selection_background"),
        (19, "selection_foreground"),
    ]
    for code, key in osc_map:
        if key in colors:
            parts.append(f"\033]{code};{colors[key]}\007")

    for i in range(16):
        key = f"color{i}"
        if key in colors:
            parts.append(f"\033]4;{i};{colors[key]}\007")

    return "".join(parts).encode("utf-8")


def emit_live_osc_to_ttys():
    """Emit OSC sequences directly to all active OmaGuake tmux client and pane TTYs."""
    osc_bytes = build_osc_bytes()
    if not osc_bytes:
        return

    ttys = set()
    for subcmd in [
        ["tmux", "-L", "omaguake", "list-clients", "-F", "#{client_tty}"],
        ["tmux", "-L", "omaguake", "list-panes", "-a", "-F", "#{pane_tty}"],
    ]:
        try:
            proc = subprocess.run(
                subcmd,
                capture_output=True,
                text=True,
                timeout=1.0,
            )
            if proc.returncode == 0:
                for line in proc.stdout.splitlines():
                    t = line.strip()
                    if t.startswith("/dev/pts/"):
                        ttys.add(t)
        except Exception:
            pass

    for tty in ttys:
        try:
            fd = os.open(tty, os.O_WRONLY | os.O_NONBLOCK)
            try:
                os.write(fd, osc_bytes)
            finally:
                os.close(fd)
        except Exception:
            pass


def main():
    parser = argparse.ArgumentParser(description="Sync Omarchy theme to OmaGuake terminals")
    parser.add_argument("--opacity", type=float, help="Unused legacy flag kept for CLI compatibility")
    parser.add_argument("--opacity-percent", type=int, help="Unused legacy flag kept for CLI compatibility")
    parser.add_argument("--notify", action="store_true", help="Notify running quickshell via IPC")
    args = parser.parse_args()

    emit_live_osc_to_ttys()

    if args.notify:
        for tgt in ["omaguake", "bramvanoploo.omaguake"]:
            try:
                subprocess.run(
                    ["omarchy-shell", tgt, "retheme"],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    timeout=1.0,
                )
            except Exception:
                pass

    print(f"Omaguake_{get_current_theme_slug()}")


if __name__ == "__main__":
    main()
