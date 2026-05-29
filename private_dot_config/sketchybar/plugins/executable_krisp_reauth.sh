#!/usr/bin/env bash
# Show a tiny menu-bar warning when krisp-sync has dropped its needs_reauth
# sentinel. Hidden otherwise.
#
# Triggered by the `krisp_reauth_changed` custom event (fired from
# krisp-sync and krisp-auth when the sentinel is written/cleared), with a
# 60s update_freq as a safety net in case a poke is missed.

NEEDS_REAUTH="$HOME/Library/Application Support/krisp-sync/needs_reauth"

if [[ -f "$NEEDS_REAUTH" ]]; then
  sketchybar --set "$NAME" drawing=on
else
  sketchybar --set "$NAME" drawing=off
fi
