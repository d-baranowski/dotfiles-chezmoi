#!/bin/bash
# Push current CPU usage (user+sys) to the graph item, and update its label.

source "$CONFIG_DIR/colors.sh"

# top -l 1 -n 0 prints "CPU usage: 12.34% user, 5.67% sys, 82.0% idle"
read -r USER_PCT SYS_PCT < <(
  top -l 1 -n 0 -s 0 \
    | awk '/CPU usage/ { gsub("%",""); print $3, $5 }'
)

# Fall back gracefully if top output changes
USER_PCT=${USER_PCT:-0}
SYS_PCT=${SYS_PCT:-0}
TOTAL=$(awk -v u="$USER_PCT" -v s="$SYS_PCT" 'BEGIN { printf "%d", u + s }')

# Push normalized 0..1 sample into the graph
NORM=$(awk -v t="$TOTAL" 'BEGIN { printf "%.2f", (t > 100 ? 1 : t/100) }')

sketchybar --push "$NAME" "$NORM" \
           --set  "$NAME" label="${TOTAL}%"
