#!/bin/bash
# Apple Silicon GPU stats via ioreg (no sudo).
# Pushes utilization into the graph and shows "<util>% <vram>G" as the label.
#
# On unified-memory Apple Silicon, "VRAM" is the GPU's wired allocation
# from system memory. We surface "In use system memory" reported by the
# IOAccelerator's PerformanceStatistics.

source "$CONFIG_DIR/colors.sh"

# Pull the IOAccelerator entry that has PerformanceStatistics with real numbers.
STATS=$(ioreg -r -d 1 -w 0 -c IOAccelerator 2>/dev/null \
  | grep -E '"PerformanceStatistics"' \
  | grep -F 'Device Utilization' \
  | head -1)

if [ -z "$STATS" ]; then
  sketchybar --set "$NAME" label="n/a"
  exit 0
fi

UTIL=$(echo "$STATS" | sed -E 's/.*"Device Utilization %"=([0-9]+).*/\1/')
VRAM_BYTES=$(echo "$STATS" | sed -E 's/.*"In use system memory"=([0-9]+).*/\1/')

UTIL=${UTIL:-0}
VRAM_BYTES=${VRAM_BYTES:-0}

# Bytes -> GiB with one decimal
VRAM_GB=$(awk -v b="$VRAM_BYTES" 'BEGIN { printf "%.1f", b/1024/1024/1024 }')

# Color the icon by utilization
if   [ "$UTIL" -ge 80 ]; then COLOR=$RED
elif [ "$UTIL" -ge 50 ]; then COLOR=$ORANGE
elif [ "$UTIL" -ge 20 ]; then COLOR=$YELLOW
else                          COLOR=$MAGENTA
fi

# Push normalized 0..1 sample into the graph
NORM=$(awk -v u="$UTIL" 'BEGIN { printf "%.2f", (u > 100 ? 1 : u/100) }')

sketchybar --push "$NAME" "$NORM" \
           --set  "$NAME" label="${UTIL}% ${VRAM_GB}G" icon.color="$COLOR"
