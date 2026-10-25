#!/usr/bin/env python3
"""
Session manager for Omaguake.
Queries running tmux sessions for active command, cwd, or restores session list.
"""

import json
import re
import subprocess
import sys

SOCKET = "omaguake"
SAFE_SESSION_RE = re.compile(r"^[a-zA-Z0-9_.][a-zA-Z0-9_.-]*$")


def normalize_session_name(name):
    s = str(name or "").strip()
    if not s.startswith("omaguake_tab_"):
        s = f"omaguake_tab_{s}"
    if not SAFE_SESSION_RE.match(s):
        return None
    return s


def list_sessions():
    proc = subprocess.run(
        [
            "tmux",
            "-L",
            SOCKET,
            "list-panes",
            "-a",
            "-F",
            "#{session_name}|#{pane_current_command}|#{pane_current_path}|#{pane_title}",
        ],
        capture_output=True,
        text=True,
        timeout=2,
    )
    if proc.returncode != 0:
        print(json.dumps([]))
        return

    sessions = []
    seen = set()
    for line in proc.stdout.splitlines():
        parts = line.strip().split("|", 3)
        if len(parts) >= 3:
            s_name = parts[0]
            if s_name in seen:
                continue
            seen.add(s_name)
            cmd = parts[1]
            cwd = parts[2]
            title = parts[3] if len(parts) > 3 else ""

            tab_id = s_name.replace("omaguake_tab_", "") if s_name.startswith("omaguake_tab_") else s_name
            try:
                tab_id_int = int(tab_id)
            except ValueError:
                tab_id_int = tab_id

            sessions.append({
                "id": tab_id_int,
                "session_name": s_name,
                "command": cmd,
                "cwd": cwd,
                "title": title,
            })

    try:
        sessions.sort(key=lambda x: int(x["id"]))
    except Exception:
        pass

    print(json.dumps(sessions))


def query_session(session_name):
    target = normalize_session_name(session_name)
    if not target:
        print(json.dumps({}))
        return
    proc = subprocess.run(
        [
            "tmux",
            "-L",
            SOCKET,
            "list-panes",
            "-t",
            target,
            "-F",
            "#{pane_current_command}|#{pane_current_path}|#{pane_title}",
        ],
        capture_output=True,
        text=True,
        timeout=2,
    )
    if proc.returncode != 0 or not proc.stdout.strip():
        print(json.dumps({}))
        return

    first_line = proc.stdout.splitlines()[0]
    parts = first_line.strip().split("|", 2)
    cmd = parts[0] if len(parts) > 0 else ""
    cwd = parts[1] if len(parts) > 1 else ""
    title = parts[2] if len(parts) > 2 else ""

    print(json.dumps({
        "command": cmd,
        "cwd": cwd,
        "title": title,
    }))


def kill_session(session_name):
    target = normalize_session_name(session_name)
    if not target:
        return
    subprocess.run(
        ["tmux", "-L", SOCKET, "kill-session", "-t", target],
        capture_output=True,
        timeout=2,
    )


def main():
    if len(sys.argv) < 2 or sys.argv[1] == "list":
        list_sessions()
    elif sys.argv[1] == "query" and len(sys.argv) > 2:
        query_session(sys.argv[2])
    elif sys.argv[1] == "kill" and len(sys.argv) > 2:
        kill_session(sys.argv[2])


if __name__ == "__main__":
    try:
        main()
    except (BrokenPipeError, TimeoutError, subprocess.SubprocessError, OSError):
        print(json.dumps([] if len(sys.argv) < 2 or sys.argv[1] == "list" else {}))
