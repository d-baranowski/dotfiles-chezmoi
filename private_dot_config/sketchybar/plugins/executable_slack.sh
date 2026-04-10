#!/bin/bash
# Show Slack unread count by reading the badge text on Slack's Dock icon.
# This is the same number macOS shows on the Slack icon in the Dock.

source "$CONFIG_DIR/colors.sh"

# Returns "5", "12", "•", or "missing value" depending on Slack's state.
BADGE=$(osascript <<'EOF' 2>/dev/null
tell application "System Events"
  try
    tell process "Dock"
      set slackDock to first UI element of list 1 whose name is "Slack"
      return value of attribute "AXStatusLabel" of slackDock
    end tell
  on error
    return ""
  end try
end tell
EOF
)

# Normalize: strip whitespace, treat "missing value" as empty.
BADGE=$(echo "$BADGE" | tr -d '[:space:]')
[ "$BADGE" = "missingvalue" ] && BADGE=""

if [ -z "$BADGE" ]; then
  # No unread — dim the icon, hide label
  sketchybar --set "$NAME" \
    icon=":slack:" \
    icon.color=0x77ffffff \
    label.drawing=off
else
  # Unread — bright icon + count
  sketchybar --set "$NAME" \
    icon=":slack:" \
    icon.color=$WHITE \
    label="$BADGE" \
    label.color=$RED \
    label.drawing=on
fi
