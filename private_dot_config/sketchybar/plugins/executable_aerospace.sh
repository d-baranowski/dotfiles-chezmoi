#!/usr/bin/env bash

# make sure it's executable with:
# chmod +x ~/.config/sketchybar/plugins/aerospace.sh

source "$CONFIG_DIR/plugins/icon_map.sh"
source "$CONFIG_DIR/colors.sh"

if [ "$1" = "$FOCUSED_WORKSPACE" ]; then
  sketchybar --set $NAME background.drawing=on \
    background.color=$SPACE_ACTIVE_BG_COLOR \
    icon.color=$SPACE_ACTIVE_COLOR \
    label.color=$SPACE_ACTIVE_COLOR
else
  sketchybar --set $NAME background.drawing=off \
    icon.color=$SPACE_INACTIVE_COLOR \
    label.color=$SPACE_INACTIVE_COLOR
fi

# Update app icons for this workspace
# aerospace list-windows format: window_id | app_name | window_title
apps=$(aerospace list-windows --workspace "$1" 2>/dev/null \
  | awk -F'|' '{ gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2 }' \
  | sort -u)

icon_string=""
if [ -n "$apps" ]; then
  while IFS= read -r app; do
    [ -z "$app" ] && continue
    __icon_map "$app"
    if [ "$icon_result" != ":default:" ]; then
      # space-separate glyphs so they don't visually touch
      if [ -z "$icon_string" ]; then
        icon_string="$icon_result"
      else
        icon_string+=" $icon_result"
      fi
    fi
  done <<< "$apps"
fi

if [ -n "$icon_string" ]; then
  sketchybar --set $NAME label="$icon_string" label.drawing=on
else
  sketchybar --set $NAME label.drawing=off
fi
