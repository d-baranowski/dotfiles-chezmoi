#!/usr/bin/env python3
"""Preview a Claude Code session by session ID."""
import json
import os
import glob
import re
import sys

if len(sys.argv) < 2:
    print("Usage: claude-session-preview.py <session-id>")
    sys.exit(1)

sid = sys.argv[1]
base = os.path.expanduser("~/.claude/projects")

for jsonl in glob.glob(os.path.join(base, "**", sid + ".jsonl"), recursive=True):
    project = os.path.basename(os.path.dirname(jsonl))
    print("Project: " + project)
    print("Session: " + sid)
    print("-" * 60)
    try:
        with open(jsonl) as f:
            turn = 0
            for line in f:
                d = json.loads(line.strip())
                role = d.get("type", "")
                if role not in ("user", "assistant"):
                    continue
                msg = d.get("message", {}).get("content", "")
                if isinstance(msg, list):
                    parts = []
                    for c in msg:
                        if isinstance(c, dict) and c.get("type") == "text":
                            parts.append(c["text"])
                    msg = " ".join(parts)
                if not msg:
                    continue
                msg = re.sub(r"<[^>]+>", "", msg).strip()
                if not msg:
                    continue
                prefix = ">>> USER" if role == "user" else "<<< CLAUDE"
                print("\n" + prefix + ":")
                print(msg[:500])
                turn += 1
                if turn > 20:
                    print("\n... (truncated)")
                    break
    except Exception as e:
        print("Error: " + str(e))
    break
