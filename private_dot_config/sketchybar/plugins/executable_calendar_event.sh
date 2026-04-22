#!/bin/sh

source "$CONFIG_DIR/colors.sh"

# Write shared events cache for Hammerspoon. Runs here because sketchybar has
# Full Calendar Access granted; Hammerspoon.app lacks NSCalendarsFullAccessUsageDescription
# and so can't read EventKit directly on macOS 14+.
# Note: sketchybar only exports CONFIG_DIR to plugin children, not PLUGIN_DIR.
CALENDAR_CACHE="$HOME/Library/Caches/hammerspoon-calendar-events.json"
/opt/homebrew/bin/icalBuddy -sc -n -nc -ea -nrd \
  -tf '%H:%M' -df '%Y-%m-%d' \
  -iep 'title,datetime,location,url,notes' \
  -b '§§' \
  eventsToday+1 2>/dev/null | \
  /usr/bin/python3 "$CONFIG_DIR/plugins/calendar_cache.py" "$CALENDAR_CACHE" 2>/dev/null

# Restrict this item to external monitors only.
# DirectDisplayID=1 is the Apple Silicon built-in panel; any other ID is external.
# We output a comma-separated list of arrangement-ids for external displays, or
# empty if the laptop panel is the only connected display.
EXTERNAL_DISPLAYS=$(sketchybar --query displays 2>/dev/null | \
  /usr/bin/jq -r '[.[] | select(.DirectDisplayID != 1) | .["arrangement-id"]] | join(",")')

if [ -z "$EXTERNAL_DISPLAYS" ]; then
  # No external monitor connected — hide the item entirely.
  sketchybar --set "$NAME" drawing=off
  exit 0
fi
sketchybar --set "$NAME" drawing=on display="$EXTERNAL_DISPLAYS"

# Get upcoming timed events today (excluding all-day events)
OUTPUT=$(icalBuddy -n -nc -npn -ea -li 10 -tf '%H:%M' -df '' -b '•' eventsToday 2>/dev/null)

LABEL=""
CURRENT_TIME=$(date +%H:%M)
CURRENT_MINUTES=$(echo "$CURRENT_TIME" | awk -F: '{print $1*60 + $2}')

if [ -n "$OUTPUT" ] && [ "$OUTPUT" != "" ]; then
  # Create temporary file to process events
  TEMP_FILE=$(mktemp)
  echo "$OUTPUT" > "$TEMP_FILE"
  
  CURRENT_EVENT_TITLE=""
  
  while IFS= read -r line; do
    if echo "$line" | grep -q '^•'; then
      # This is a title line
      CURRENT_EVENT_TITLE=$(echo "$line" | sed 's/^•[[:space:]]*//')
    elif echo "$line" | grep -q '^[[:space:]]*[0-9][0-9]:[0-9][0-9]'; then
      # This is a time line
      EVENT_TIME=$(echo "$line" | grep -o '^[[:space:]]*[0-9][0-9]:[0-9][0-9]' | xargs)
      
      if [ -n "$EVENT_TIME" ] && [ -n "$CURRENT_EVENT_TITLE" ]; then
        EVENT_START_MINUTES=$(echo "$EVENT_TIME" | awk -F: '{print $1*60 + $2}')
        TIME_DIFF=$((CURRENT_MINUTES - EVENT_START_MINUTES))
        
        # Show this event if:
        # 1. It hasn't started yet (TIME_DIFF < 0), OR  
        # 2. It started less than 5 minutes ago (0 <= TIME_DIFF <= 5)
        if [ $TIME_DIFF -le 5 ]; then
          LABEL="$EVENT_TIME $CURRENT_EVENT_TITLE"
          break
        fi
      fi
      CURRENT_EVENT_TITLE=""
    fi
  done < "$TEMP_FILE"
  
  rm -f "$TEMP_FILE"
fi

# Update sketchybar - adjust padding based on content
if [ -z "$LABEL" ]; then
  # Icon only - centered padding accounting for internal icon-label spacing
  # Shift slightly right to compensate for internal spacing
  sketchybar --set "$NAME" \
    icon=":calendar:" \
    icon.color="$WHITE" \
    icon.padding_left=8 \
    icon.padding_right=8 \
    label="" \
    label.padding_right=0
else
  # Icon with label - normal padding
  sketchybar --set "$NAME" \
    icon=":calendar:" \
    icon.color="$WHITE" \
    icon.padding_left=8 \
    icon.padding_right=6 \
    label="$LABEL" \
    label.color="$CAL_EVENT_LABEL_COLOR" \
    label.padding_right=10
fi
