#!/bin/bash
# Sketchybar plugin: mute toggle for Claude notification sounds.
# Click toggles mute state. Icon reflects current state.

source "$CONFIG_DIR/colors.sh"

MUTE_FILE="/tmp/claude-notify-muted"

update_icon() {
  if [ -f "$MUTE_FILE" ]; then
    # Muted — speaker off
    sketchybar --set "$NAME" \
      icon="󰝟" \
      icon.color=0x77ffffff
  else
    # Unmuted — speaker on
    sketchybar --set "$NAME" \
      icon="󰕾" \
      icon.color=$WHITE
  fi
}

handle_click() {
  if [ -f "$MUTE_FILE" ]; then
    rm -f "$MUTE_FILE"
  else
    touch "$MUTE_FILE"
  fi
  update_icon
}

case "$SENDER" in
  "mouse.clicked") handle_click ;;
  *)               update_icon ;;
esac
