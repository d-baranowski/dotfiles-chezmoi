#!/bin/bash
# Wrapper around macOS `screencapture` that always writes to a known folder
# with a timestamped filename, so you can find captures later.
#
# Usage:
#   screenshot.sh area      # interactive area selection (default)
#   screenshot.sh full      # whole screen, no UI
#   screenshot.sh window    # interactive window selection
#   screenshot.sh record    # opens the macOS ⌘⇧5 capture toolbar
#   screenshot.sh open      # reveal the screenshots folder in Finder

SHOTS_DIR="$HOME/Pictures/Screenshots"
mkdir -p "$SHOTS_DIR"

mode="${1:-area}"
ts=$(date +%Y-%m-%d_%H-%M-%S)

case "$mode" in
  area)
    # -i interactive, -x silent shutter
    /usr/sbin/screencapture -i -x "$SHOTS_DIR/screenshot-$ts.png"
    ;;
  full)
    /usr/sbin/screencapture -x "$SHOTS_DIR/screenshot-$ts.png"
    ;;
  window)
    # -W window selection
    /usr/sbin/screencapture -i -W -x "$SHOTS_DIR/screenshot-$ts.png"
    ;;
  record)
    # screencapture -v records video; the macOS capture toolbar (⌘⇧5) is
    # nicer for recording because it shows controls. Trigger it via keystroke.
    osascript -e 'tell application "System Events" to keystroke "5" using {command down, shift down}'
    ;;
  open)
    open "$SHOTS_DIR"
    ;;
  *)
    echo "unknown mode: $mode" >&2
    exit 1
    ;;
esac
