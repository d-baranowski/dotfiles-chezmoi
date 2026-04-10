#!/usr/bin/env bash
# Open Google Calendar in a new Chrome window and move it to workspace T
# once the title resolves (the title-based on-window-detected rule can't see
# "Google Calendar" until Chrome finishes loading the page).

open -na 'Google Chrome' --args --new-window https://calendar.google.com

# Poll up to ~5s for the calendar window to appear, then move + focus.
for _ in $(seq 1 25); do
  win=$(aerospace list-windows --all --format '%{window-id}|%{app-name}|%{window-title}' \
    | awk -F'|' 'tolower($2) ~ /chrome/ && tolower($3) ~ /(calendar|kalendarz)/ { print $1; exit }' \
    | tr -d '[:space:]')
  if [ -n "$win" ]; then
    aerospace move-node-to-workspace --window-id "$win" T
    aerospace workspace T
    exit 0
  fi
  sleep 0.2
done
