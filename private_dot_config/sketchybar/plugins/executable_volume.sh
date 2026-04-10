#!/bin/bash

source "$CONFIG_DIR/colors.sh"

# Adjust volume on scroll
if [ "$SENDER" = "mouse.scrolled" ]; then
  CURRENT=$(osascript -e 'output volume of (get volume settings)')
  STEP=$(( SCROLL_DELTA > 0 ? 5 : -5 ))
  NEW=$(( CURRENT + STEP ))
  [ $NEW -lt 0 ]   && NEW=0
  [ $NEW -gt 100 ] && NEW=100
  osascript -e "set volume output volume $NEW"
  VOLUME=$NEW
elif [ "$SENDER" = "volume_change" ]; then
  VOLUME="$INFO"
else
  # Initial render / forced update
  VOLUME=$(osascript -e 'output volume of (get volume settings)')
fi

MUTED=$(osascript -e 'output muted of (get volume settings)' 2>/dev/null)

if [ "$MUTED" = "true" ]; then
  ICON="󰖁"
else
  case "$VOLUME" in
    [6-9][0-9]|100) ICON="󰕾" ;;
    [3-5][0-9])     ICON="󰖀" ;;
    [1-9]|[1-2][0-9]) ICON="󰕿" ;;
    *)              ICON="󰖁" ;;
  esac
fi

sketchybar --set "$NAME" \
  icon="$ICON" \
  icon.color="$VOLUME_COLOR" \
  label="${VOLUME}%" \
  label.color="$VOLUME_COLOR"
