#!/usr/bin/env python3
import sys
import os
import re
import json
import subprocess
from pathlib import Path

HOME = Path(os.environ.get("HOME", "/home/bram"))
HYPR_DIR = HOME / ".config" / "hypr"
BINDINGS_LUA = HYPR_DIR / "bindings.lua"

MOD_MAP = {
    "super": 64,
    "mod4": 64,
    "logo": 64,
    "win": 64,
    "ctrl": 4,
    "control": 4,
    "shift": 1,
    "alt": 8,
    "mod1": 8,
}

def normalize_key_chord(chord_str):
    if not chord_str:
        return None, 0, ""
    cleaned = chord_str.strip().replace("+", " ").replace(",", " ")
    tokens = [t.strip() for t in cleaned.split() if t.strip()]
    if not tokens:
        return None, 0, ""
    
    mods = 0
    mod_names = []
    key = ""
    for token in tokens:
        tl = token.lower()
        if tl in MOD_MAP:
            mods |= MOD_MAP[tl]
            mod_names.append(tl.upper())
        else:
            key = token.upper()
    
    return "+".join(sorted(mod_names)) + " + " + key if mod_names else key, mods, key

def get_hyprctl_binds():
    try:
        out = subprocess.check_output(["hyprctl", "binds", "-j"], timeout=3)
        return json.loads(out)
    except Exception:
        return []

def check_key_conflict(candidate_chord):
    norm, target_mods, target_key = normalize_key_chord(candidate_chord)
    if not target_key:
        return {
            "conflict": True,
            "message": "Invalid keybinding string."
        }
    
    binds = get_hyprctl_binds()
    for b in binds:
        # Ignore bindings created by bramvanoploo.omaguake itself
        desc = b.get("description", "") or ""
        arg = b.get("arg", "") or ""
        disp = b.get("dispatcher", "") or ""
        if "bramvanoploo.omaguake" in arg or "bramvanoploo.omaguake" in desc:
            continue
        
        b_key = str(b.get("key", "")).upper()
        b_modmask = int(b.get("modmask", 0))
        
        # Check match
        if b_key == target_key and b_modmask == target_mods:
            conflict_label = desc or arg or disp or "system action"
            return {
                "conflict": True,
                "message": f"Conflicts with existing binding: '{norm}' is assigned to '{conflict_label}'."
            }
    
    # Also scan bindings.lua for un-dispatched or commented out bindings
    if BINDINGS_LUA.exists():
        try:
            content = BINDINGS_LUA.read_text(encoding="utf-8")
            # Exclude our own block
            sub = re.sub(r"-- BEGIN bramvanoploo\.omaguake.*?-- END bramvanoploo\.omaguake", "", content, flags=re.DOTALL)
            for line in sub.splitlines():
                line = line.strip()
                if line.startswith("--"):
                    continue
                m = re.search(r'bind\s*\(\s*["\']([^"\']+)["\']\s*,\s*(?:["\']([^"\']*)["\']|[^,\)]+)', line)
                if m:
                    b_chord = m.group(1)
                    b_norm, b_mods, b_k = normalize_key_chord(b_chord)
                    if b_k == target_key and b_mods == target_mods:
                        desc = m.group(2) if len(m.groups()) > 1 and m.group(2) else "custom Hyprland binding"
                        return {
                            "conflict": True,
                            "message": f"Conflicts with binding in ~/.config/hypr/bindings.lua: '{norm}' -> '{desc}'."
                        }
        except Exception:
            pass

    return {
        "conflict": False,
        "message": f"Keybinding '{norm}' is available."
    }

def check_gesture_conflict():
    # Check 3-finger swipe gestures
    # In Hyprland, check if 3-finger drag is enabled
    # Check t2-trackpad.lua and input.lua
    files_to_check = [
        HYPR_DIR / "t2-trackpad.lua",
        HYPR_DIR / "input.lua",
        HYPR_DIR / "hyprland.lua"
    ]
    
    for f in files_to_check:
        if not f.exists():
            continue
        try:
            content = f.read_text(encoding="utf-8")
            # Exclude our own block
            content = re.sub(r"-- BEGIN bramvanoploo\.omaguake.*?-- END bramvanoploo\.omaguake", "", content, flags=re.DOTALL)
            
            # Check active lines only
            for line in content.splitlines():
                line = line.strip()
                if line.startswith("--"):
                    continue
                # Check 3-finger drag
                if re.search(r'drag_3fg\s*=\s*([123]|true)', line):
                    return {
                        "conflict": True,
                        "message": f"Three-finger drag is enabled in {f.name}, which prevents 3-finger swipe gestures."
                    }
                if "hl.gesture" in line or "gesture" in line:
                    if re.search(r'fingers\s*=\s*3', line) and re.search(r'direction\s*=\s*["\'](down|up|vertical)["\']', line):
                        return {
                            "conflict": True,
                            "message": f"Three-finger vertical gesture already configured in {f.name}."
                        }
        except Exception:
            pass
            
    return {
        "conflict": False,
        "message": "3-finger swipe down (show) and swipe up (hide) gestures are available."
    }

def apply_configuration(keychord, enable_gestures):
    # First check conflicts
    key_res = check_key_conflict(keychord)
    if key_res["conflict"]:
        return {"success": False, "error": key_res["message"]}
        
    if enable_gestures:
        gest_res = check_gesture_conflict()
        if gest_res["conflict"]:
            return {"success": False, "error": gest_res["message"]}
            
    norm_chord, _, _ = normalize_key_chord(keychord)
    
    # Update bindings.lua
    BINDINGS_LUA.parent.mkdir(parents=True, exist_ok=True)
    existing = ""
    if BINDINGS_LUA.exists():
        existing = BINDINGS_LUA.read_text(encoding="utf-8")
        
    # Remove old block if exists
    cleaned = re.sub(r"\n*-- BEGIN bramvanoploo\.omaguake.*?-- END bramvanoploo\.omaguake\n*", "\n", existing, flags=re.DOTALL).strip()
    
    block_lines = [
        "",
        "-- BEGIN bramvanoploo.omaguake",
        f'hl.bind("{norm_chord}", hl.dsp.global("bramvanoploo.omaguake:toggle"))',
    ]
    if enable_gestures:
        block_lines.append('-- Omaguake Gestures: 3-finger swipe down to show, swipe up to hide')
        block_lines.append('hl.gesture({ fingers = 3, direction = "down", action = function() hl.dispatch(hl.dsp.global("bramvanoploo.omaguake:show")) end })')
        block_lines.append('hl.gesture({ fingers = 3, direction = "up", action = function() hl.dispatch(hl.dsp.global("bramvanoploo.omaguake:hide")) end })')
    block_lines.append("-- END bramvanoploo.omaguake")
    block_lines.append("")
    
    new_content = cleaned + "\n" + "\n".join(block_lines)
    BINDINGS_LUA.write_text(new_content, encoding="utf-8")
    
    # Reload hyprland
    try:
        subprocess.run(["hyprctl", "reload"], timeout=3)
    except Exception:
        pass
        
    return {"success": True, "message": "Keybinding and gestures applied successfully."}

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(json.dumps({"error": "No action specified"}))
        sys.exit(1)
        
    action = sys.argv[1]
    if action == "check-key":
        chord = sys.argv[2] if len(sys.argv) > 2 else "CTRL + SPACE"
        print(json.dumps(check_key_conflict(chord)))
    elif action == "check-gesture":
        print(json.dumps(check_gesture_conflict()))
    elif action == "apply":
        chord = sys.argv[2] if len(sys.argv) > 2 else "CTRL + SPACE"
        enable_gest = True
        if len(sys.argv) > 3:
            enable_gest = sys.argv[3].lower() in ["1", "true", "yes"]
        res = apply_configuration(chord, enable_gest)
        print(json.dumps(res))
        if not res.get("success"):
            sys.exit(1)
    else:
        print(json.dumps({"error": f"Unknown action: {action}"}))
        sys.exit(1)
