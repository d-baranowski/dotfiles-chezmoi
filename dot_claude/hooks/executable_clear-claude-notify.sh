#!/bin/bash
# Claude Code hook: clear notification for the current tmux session.
# Called on UserPromptSubmit — the user is back, so dismiss the bell.

STATE_FILE="/tmp/claude-notifications.json"

TMUX_SESSION="default"
if [ -n "$TMUX" ]; then
  TMUX_SESSION=$(tmux display-message -p '#S' 2>/dev/null || echo "default")
fi

[ ! -f "$STATE_FILE" ] && exit 0

jq --arg s "$TMUX_SESSION" '[.[] | select(.session != $s)]' "$STATE_FILE" > "${STATE_FILE}.tmp" 2>/dev/null && \
  mv "${STATE_FILE}.tmp" "$STATE_FILE"

sketchybar --trigger claude_notification 2>/dev/null

exit 0
