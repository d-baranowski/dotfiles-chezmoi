#!/bin/bash
# Show the number of running Docker containers.
#
# Sketchybar runs plugins under launchd with a stripped PATH, so docker
# (typically in /usr/local/bin or /opt/homebrew/bin) isn't on PATH unless we
# add it ourselves.
export PATH="/usr/local/bin:/opt/homebrew/bin:$PATH"

source "$CONFIG_DIR/colors.sh"

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  COUNT=$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')
  sketchybar --set "$NAME" \
    drawing=on \
    icon="󰡨" \
    label="$COUNT"
else
  # Docker daemon not running — hide the item rather than show 0
  sketchybar --set "$NAME" drawing=off
fi
