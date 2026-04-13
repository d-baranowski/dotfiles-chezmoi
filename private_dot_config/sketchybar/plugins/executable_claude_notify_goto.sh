#!/bin/bash
# Navigate to the most recent Claude notification's workspace + tmux session.
# Same as clicking the bell icon in Sketchybar, but callable standalone.

STATE_FILE="/tmp/claude-notifications.json"

[ ! -f "$STATE_FILE" ] && exit 0

ENTRY=$(jq -r 'sort_by(.ts) | last' "$STATE_FILE" 2>/dev/null)
[ "$ENTRY" = "null" ] || [ -z "$ENTRY" ] && exit 0

WORKSPACE=$(echo "$ENTRY" | jq -r '.workspace')
SESSION=$(echo "$ENTRY" | jq -r '.session')

# Switch aerospace workspace
if [ -n "$WORKSPACE" ] && [ "$WORKSPACE" != "null" ]; then
  /opt/homebrew/bin/aerospace workspace "$WORKSPACE" 2>/dev/null
fi

# Focus the terminal
open -a Alacritty

# Switch to the tmux session
if [ -n "$SESSION" ] && [ "$SESSION" != "null" ] && [ "$SESSION" != "default" ]; then
  tmux switch-client -t "$SESSION" 2>/dev/null
fi

# Remove only the actioned notification (match by timestamp)
TS=$(echo "$ENTRY" | jq -r '.ts')
jq --arg ts "$TS" '[.[] | select(.ts != ($ts | tonumber))]' "$STATE_FILE" > "${STATE_FILE}.tmp" \
  && mv "${STATE_FILE}.tmp" "$STATE_FILE"
sketchybar --trigger claude_notification 2>/dev/null
