#!/usr/bin/env python3
"""
Detect universal copy and paste keybindings configured in Hyprland/Omarchy
and write them to clipboard_binds.json for Omaguake to capture and translate.
Supports one-shot execution or daemon mode (--watch) monitoring Hyprland reload events.
"""

import argparse
import json
import os
import pathlib
import select
import socket
import sys

# Runtime state lives outside the plugin directory: Omarchy 4.5 watches
# everything under ~/.config/omarchy/plugins/ and reloads the plugin on any
# save there, so writing clipboard_binds.json in-place reloaded the whole
# plugin on every Hyprland config reload. Use Omarchy's own state convention
# (~/.local/state/omarchy/<plugin-id>/), same location as settings.json.
def get_state_dir():
    state_home = os.environ.get("XDG_STATE_HOME") or ""
    if not state_home:
        state_home = str(pathlib.Path.home() / ".local" / "state")
    return pathlib.Path(state_home) / "omarchy" / "bramvanoploo.omaguake"


OUTPUT_FILE = get_state_dir() / "clipboard_binds.json"

def get_hyprland_binds():
    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    uid = os.getuid()
    if sig:
        sock_path = f"/run/user/{uid}/hypr/{sig}/.socket.sock"
        if os.path.exists(sock_path):
            try:
                s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                s.settimeout(1.0)
                s.connect(sock_path)
                s.sendall(b"j/binds")
                raw = b""
                max_bytes = 4 * 1024 * 1024
                while True:
                    chunk = s.recv(8192)
                    if not chunk:
                        break
                    raw += chunk
                    if len(raw) > max_bytes:
                        s.close()
                        raise RuntimeError("hyprland socket response too large")
                s.close()
                return json.loads(raw.decode("utf-8", errors="replace"))
            except Exception:
                pass

    import subprocess
    out = subprocess.check_output(["hyprctl", "binds", "-j"], timeout=2)
    return json.loads(out)

def extract_clipboard_binds():
    try:
        binds = get_hyprland_binds()
    except Exception as e:
        sys.stderr.write(f"Error fetching Hyprland binds: {e}\n")
        return {
            "copy": [{"modmask": 64, "key": "C"}],
            "paste": [{"modmask": 64, "key": "V"}]
        }

    copy_binds = []
    paste_binds = []

    for b in binds:
        desc = (b.get("description") or "").strip().lower()
        modmask = b.get("modmask", 0)
        key = (b.get("key") or "").strip()
        if not key:
            continue

        item = {"modmask": modmask, "key": key}

        if "universal copy" in desc:
            copy_binds.append(item)
        elif "universal paste" in desc:
            paste_binds.append(item)

    # Fallback search if "universal copy/paste" was not found
    if not copy_binds:
        for b in binds:
            desc = (b.get("description") or "").strip().lower()
            if desc == "copy" or "clipboard copy" in desc:
                copy_binds.append({"modmask": b.get("modmask", 0), "key": (b.get("key") or "").strip()})
    if not paste_binds:
        for b in binds:
            desc = (b.get("description") or "").strip().lower()
            if desc == "paste" or "clipboard paste" in desc:
                paste_binds.append({"modmask": b.get("modmask", 0), "key": (b.get("key") or "").strip()})

    # Default fallback to Super+C and Super+V
    if not copy_binds:
        copy_binds.append({"modmask": 64, "key": "C"})
    if not paste_binds:
        paste_binds.append({"modmask": 64, "key": "V"})

    return {
        "copy": copy_binds,
        "paste": paste_binds
    }

def update_file():
    data = extract_clipboard_binds()
    content = json.dumps(data, indent=2) + "\n"
    try:
        if OUTPUT_FILE.exists() and OUTPUT_FILE.read_text(encoding="utf-8") == content:
            return data
        OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)
        temp_output = OUTPUT_FILE.with_suffix(f"{OUTPUT_FILE.suffix}.tmp.{os.getpid()}")
        temp_output.write_text(content, encoding="utf-8")
        temp_output.replace(OUTPUT_FILE)
    except Exception as e:
        sys.stderr.write(f"Error writing {OUTPUT_FILE}: {e}\n")
    return data

def watch_events():
    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    uid = os.getuid()
    if not sig:
        return

    sock_path = f"/run/user/{uid}/hypr/{sig}/.socket2.sock"
    if not os.path.exists(sock_path):
        return

    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.connect(sock_path)
        s.setblocking(True)
        buf = ""
        while True:
            chunk = s.recv(4096)
            if not chunk:
                break
            buf += chunk.decode("utf-8", errors="replace")
            while "\n" in buf:
                line, buf = buf.split("\n", 1)
                if line.startswith("configreloaded>>"):
                    update_file()
    except Exception as e:
        sys.stderr.write(f"Socket2 watch error: {e}\n")

def main():
    parser = argparse.ArgumentParser(description="Sync clipboard keybindings for Omaguake")
    parser.add_argument("--watch", action="store_true", help="Watch Hyprland config reloads and keep file updated")
    args = parser.parse_args()

    data = update_file()
    print(json.dumps(data))
    sys.stdout.flush()

    if args.watch:
        watch_events()

if __name__ == "__main__":
    main()
