#!/bin/bash
# Sketchybar plugin: Claude Code notification bell.
# Shows a bell icon that lights up when any Claude session needs attention.
# Click navigates to the most recent notification's workspace + tmux session.

source "$CONFIG_DIR/colors.sh"

STATE_FILE="/tmp/claude-notifications.json"

update_bell() {
  local COUNT=0
  if [ -f "$STATE_FILE" ]; then
    COUNT=$(jq 'length' "$STATE_FILE" 2>/dev/null || echo 0)
  fi

  if [ "$COUNT" -gt 0 ]; then
    # Active notifications — bright yellow bell
    if [ "$COUNT" -gt 1 ]; then
      sketchybar --set "$NAME" \
        icon="󰂞" \
        icon.color=$YELLOW \
        label="$COUNT" \
        label.drawing=on \
        label.color=$YELLOW \
        background.color="$ITEM_BG_COLOR" \
        background.drawing=on
    else
      sketchybar --set "$NAME" \
        icon="󰂞" \
        icon.color=$YELLOW \
        label.drawing=off \
        background.color="$ITEM_BG_COLOR" \
        background.drawing=on
    fi
  else
    # No notifications — dim grey bell
    sketchybar --set "$NAME" \
      icon="󰂜" \
      icon.color=0x77ffffff \
      label.drawing=off \
      background.drawing=off
  fi
}

handle_click() {
  [ ! -f "$STATE_FILE" ] && return

  # Pick the most recent notification
  local ENTRY
  ENTRY=$(jq -r 'sort_by(.ts) | last' "$STATE_FILE" 2>/dev/null)
  [ "$ENTRY" = "null" ] || [ -z "$ENTRY" ] && return

  local WORKSPACE SESSION
  WORKSPACE=$(echo "$ENTRY" | jq -r '.workspace')
  SESSION=$(echo "$ENTRY" | jq -r '.session')

  # Switch aerospace workspace
  if [ -n "$WORKSPACE" ] && [ "$WORKSPACE" != "null" ]; then
    aerospace workspace "$WORKSPACE" 2>/dev/null
  fi

  # Focus the terminal
  open -a Alacritty

  # Switch to the tmux session
  if [ -n "$SESSION" ] && [ "$SESSION" != "null" ] && [ "$SESSION" != "default" ]; then
    tmux switch-client -t "$SESSION" 2>/dev/null
  fi

  # Clear all notifications — user is looking now
  echo '[]' > "$STATE_FILE"
  sketchybar --trigger claude_notification 2>/dev/null
}

case "$SENDER" in
  "mouse.clicked") handle_click ;;
  *)               update_bell ;;
esac
