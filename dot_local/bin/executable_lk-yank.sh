#!/usr/bin/env bash
# Usage: lk-yank.sh <register-letter>
letter="$1"
osascript -e 'tell application "System Events" to keystroke "c" using command down'
sleep 0.05
cb paste | cb copy_"$letter"
