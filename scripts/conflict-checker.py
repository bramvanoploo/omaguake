#!/usr/bin/env python3
import sys
import os
import re
import json
import subprocess
from pathlib import Path

HOME = Path(os.environ.get("HOME", str(Path.home())))
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
    
    # Check if this chord is already our own binding in bindings.lua
    current_own_chord = None
    if BINDINGS_LUA.exists():
        try:
            content = BINDINGS_LUA.read_text(encoding="utf-8")
            m_own = re.search(r"-- BEGIN bramvanoploo\.omaguake.*?hl\.bind\(\s*[\"']([^\"']+)[\"'].*?-- END bramvanoploo\.omaguake", content, flags=re.DOTALL)
            if m_own:
                current_own_chord, _, _ = normalize_key_chord(m_own.group(1))
        except Exception:
            pass
            
    if current_own_chord and norm == current_own_chord:
        return {
            "conflict": False,
            "message": f"Keybinding '{norm}' is currently assigned to Omaguake."
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

def find_free_suggestions(exclude_chord=None):
    candidates = [
        "F12",
        "CTRL + SPACE",
        "CTRL + GRAVE",
        "SUPER + GRAVE",
        "ALT + SPACE",
        "CTRL + ALT + T",
        "SUPER + F12",
        "ALT + F12",
        "CTRL + BACKQUOTE"
    ]
    norm_exclude = normalize_key_chord(exclude_chord)[0] if exclude_chord else ""
    free_suggestions = []
    
    binds = get_hyprctl_binds()
    bind_keys = set()
    for b in binds:
        bk = str(b.get("key", "")).upper()
        bm = int(b.get("modmask", 0))
        bind_keys.add((bm, bk))
        
    for cand in candidates:
        norm, mods, key = normalize_key_chord(cand)
        if not norm or norm == norm_exclude:
            continue
        if (mods, key) not in bind_keys:
            free_suggestions.append(norm)
            if len(free_suggestions) >= 3:
                break
    return free_suggestions

def check_gesture_conflict(fingers=3):
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
            
            for line in content.splitlines():
                line = line.strip()
                if line.startswith("--"):
                    continue
                if fingers == 3 and re.search(r'drag_3fg\s*=\s*([123]|true)', line):
                    return {
                        "conflict": True,
                        "message": f"Three-finger drag is enabled in {f.name}, which prevents 3-finger swipe gestures."
                    }
                if "hl.gesture" in line or "gesture" in line:
                    if re.search(rf'fingers\s*=\s*{fingers}', line) and re.search(r'direction\s*=\s*["\'](down|up|vertical)["\']', line):
                        return {
                            "conflict": True,
                            "message": f"{fingers}-finger vertical gesture is already configured in {f.name}."
                        }
        except Exception:
            pass
            
    return {
        "conflict": False,
        "message": f"{fingers}-finger swipe down (show) and swipe up (hide) gestures are available."
    }

def get_current_omaguake_status():
    applied_key = ""
    applied_gestures = False
    applied_fingers = 3
    
    if BINDINGS_LUA.exists():
        try:
            content = BINDINGS_LUA.read_text(encoding="utf-8")
            m_block = re.search(r"-- BEGIN bramvanoploo\.omaguake(.*?)-- END bramvanoploo\.omaguake", content, flags=re.DOTALL)
            if m_block:
                block_txt = m_block.group(1)
                m_bind = re.search(r'hl\.bind\(\s*["\']([^"\']+)["\']', block_txt)
                if m_bind:
                    applied_key = normalize_key_chord(m_bind.group(1))[0]
                m_gest = re.search(r'hl\.gesture\(\s*\{\s*fingers\s*=\s*(\d+)', block_txt)
                if m_gest:
                    applied_gestures = True
                    applied_fingers = int(m_gest.group(1))
        except Exception:
            pass
            
    # Check suggested key (CTRL + SPACE)
    # To check if it's used by someone OTHER than Omaguake:
    suggested_chord = "CTRL + SPACE"
    suggested_norm, s_mods, s_key = normalize_key_chord(suggested_chord)
    s_conflict = False
    s_conflict_msg = ""
    binds = get_hyprctl_binds()
    for b in binds:
        desc = b.get("description", "") or ""
        arg = b.get("arg", "") or ""
        disp = b.get("dispatcher", "") or ""
        if "bramvanoploo.omaguake" in arg or "bramvanoploo.omaguake" in desc:
            continue
        if applied_key == suggested_norm:
            # It's currently ours
            continue
        b_key = str(b.get("key", "")).upper()
        b_modmask = int(b.get("modmask", 0))
        if b_key == s_key and b_modmask == s_mods:
            conflict_label = desc or arg or disp or "system action"
            s_conflict = True
            s_conflict_msg = f"'{suggested_norm}' is in use by '{conflict_label}'."
            break
            
    gest_res = check_gesture_conflict(3)
    
    return {
        "applied_key": applied_key,
        "applied_gestures": applied_gestures,
        "applied_gesture_fingers": applied_fingers,
        "suggested_key": suggested_chord,
        "suggested_key_conflict": s_conflict,
        "suggested_key_conflict_message": s_conflict_msg,
        "suggested_gesture_conflict": gest_res["conflict"],
        "suggested_gesture_conflict_message": gest_res["message"] if gest_res["conflict"] else "",
        "key_suggestions": find_free_suggestions(suggested_chord if s_conflict else "")
    }

def apply_configuration(keychord, enable_gestures, gesture_fingers=3, unbind_conflicts=False):
    norm_chord = ""
    if keychord and keychord.strip() and keychord.strip().lower() not in ["none", ""]:
        norm_chord, _, _ = normalize_key_chord(keychord)
        # If not unbinding, verify conflicts
        if not unbind_conflicts:
            key_res = check_key_conflict(norm_chord)
            if key_res["conflict"]:
                return {"success": False, "error": key_res["message"]}
        
    if enable_gestures:
        gest_res = check_gesture_conflict(gesture_fingers)
        if gest_res["conflict"]:
            return {"success": False, "error": gest_res["message"]}
            
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
        'hl.layer_rule({ match = { namespace = "omaguake" }, blur = true, no_anim = true, animation = "none" })',
    ]
    if norm_chord:
        if unbind_conflicts:
            block_lines.append(f'hl.unbind("{norm_chord}")')
        block_lines.append(f'hl.bind("{norm_chord}", hl.dsp.global("bramvanoploo.omaguake:toggle"))')
        
    if enable_gestures:
        block_lines.append(f'-- Omaguake Gestures: {gesture_fingers}-finger swipe down to show, swipe up to hide')
        block_lines.append(f'hl.gesture({{ fingers = {gesture_fingers}, direction = "down", action = function() hl.dispatch(hl.dsp.global("bramvanoploo.omaguake:show")) end, disable_inhibit = true }})')
        block_lines.append(f'hl.gesture({{ fingers = {gesture_fingers}, direction = "up", action = function() hl.dispatch(hl.dsp.global("bramvanoploo.omaguake:hide")) end, disable_inhibit = true }})')
        
    block_lines.append("-- END bramvanoploo.omaguake")
    block_lines.append("")
    
    new_content = cleaned + "\n" + "\n".join(block_lines)
    temp_binding = BINDINGS_LUA.with_suffix(".tmp")
    try:
        temp_binding.write_text(new_content, encoding="utf-8")
        temp_binding.replace(BINDINGS_LUA)
    except Exception:
        BINDINGS_LUA.write_text(new_content, encoding="utf-8")
    
    # Reload hyprland
    try:
        subprocess.run(["hyprctl", "reload"], timeout=3)
    except Exception:
        pass
        
    return {"success": True, "message": "Omaguake bindings updated successfully."}

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(json.dumps({"error": "No action specified"}))
        sys.exit(1)
        
    action = sys.argv[1]
    if action == "status":
        print(json.dumps(get_current_omaguake_status()))
    elif action == "check-key":
        chord = sys.argv[2] if len(sys.argv) > 2 else ""
        res = check_key_conflict(chord)
        if res.get("conflict"):
            res["suggestions"] = find_free_suggestions(chord)
        print(json.dumps(res))
    elif action == "check-gesture":
        f_count = int(sys.argv[2]) if len(sys.argv) > 2 and sys.argv[2].isdigit() else 3
        print(json.dumps(check_gesture_conflict(f_count)))
    elif action == "apply":
        chord = sys.argv[2] if len(sys.argv) > 2 else ""
        if chord.lower() in ["none", '""', "''"]:
            chord = ""
        enable_gest = False
        if len(sys.argv) > 3:
            enable_gest = sys.argv[3].lower() in ["1", "true", "yes"]
        f_count = 3
        if len(sys.argv) > 4 and sys.argv[4].isdigit():
            f_count = int(sys.argv[4])
        unbind_conf = False
        if len(sys.argv) > 5:
            unbind_conf = sys.argv[5].lower() in ["1", "true", "yes"]
        res = apply_configuration(chord, enable_gest, f_count, unbind_conf)
        print(json.dumps(res))
        if not res.get("success"):
            sys.exit(1)
    else:
        print(json.dumps({"error": f"Unknown action: {action}"}))
        sys.exit(1)
