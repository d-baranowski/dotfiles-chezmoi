#!/usr/bin/env bash
# Usage: lk-paste.sh <register-letter>
letter="$1"
cb paste_"$letter" | pbcopy
osascript -e 'tell application "System Events" to keystroke "v" using command down'
