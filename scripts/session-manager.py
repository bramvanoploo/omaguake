#!/usr/bin/env python3
"""
Session manager for Omaguake.
Queries running tmux sessions for active command, cwd, or restores session list.
"""

import json
import subprocess
import sys

SOCKET = "omaguake"


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
    )
    if proc.returncode != 0:
        print(json.dumps([]))
        return

    sessions = []
    seen = set()
    for line in proc.stdout.splitlines():
        parts = line.strip().split("|")
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
                "title": title
            })

    # Sort numerically if integer IDs
    try:
        sessions.sort(key=lambda x: int(x["id"]))
    except Exception:
        pass

    print(json.dumps(sessions))


def query_session(session_name):
    if not session_name.startswith("omaguake_tab_"):
        session_name = f"omaguake_tab_{session_name}"
    proc = subprocess.run(
        [
            "tmux",
            "-L",
            SOCKET,
            "list-panes",
            "-t",
            session_name,
            "-F",
            "#{pane_current_command}|#{pane_current_path}|#{pane_title}",
        ],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0 or not proc.stdout.strip():
        print(json.dumps({}))
        return

    first_line = proc.stdout.splitlines()[0]
    parts = first_line.strip().split("|")
    cmd = parts[0] if len(parts) > 0 else ""
    cwd = parts[1] if len(parts) > 1 else ""
    title = parts[2] if len(parts) > 2 else ""

    print(json.dumps({
        "command": cmd,
        "cwd": cwd,
        "title": title
    }))


def kill_session(session_name):
    if not session_name.startswith("omaguake_tab_"):
        session_name = f"omaguake_tab_{session_name}"
    subprocess.run(["tmux", "-L", SOCKET, "kill-session", "-t", session_name], capture_output=True)


def main():
    if len(sys.argv) < 2 or sys.argv[1] == "list":
        list_sessions()
    elif sys.argv[1] == "query" and len(sys.argv) > 2:
        query_session(sys.argv[2])
    elif sys.argv[1] == "kill" and len(sys.argv) > 2:
        kill_session(sys.argv[2])


if __name__ == "__main__":
    main()
