#!/bin/bash
# Claude Code hook: record notification and trigger sketchybar bell.
# Detects workspace dynamically by walking the process tree to find
# the terminal app, then locating it in aerospace.

STATE_FILE="/tmp/claude-notifications.json"

# --- Detect tmux session ---
TMUX_SESSION="default"
if [ -n "$TMUX" ]; then
  TMUX_SESSION=$(tmux display-message -p '#S' 2>/dev/null || echo "default")
fi

# --- Detect aerospace workspace ---
detect_workspace() {
  local TERM_APP=""

  if [ -n "$TMUX" ]; then
    local CLIENT_PID
    CLIENT_PID=$(tmux display-message -p '#{client_pid}' 2>/dev/null)
    if [ -n "$CLIENT_PID" ]; then
      local PID="$CLIENT_PID"
      local DEPTH=0
      while [ -n "$PID" ] && [ "$PID" != "1" ] && [ "$PID" != "0" ] && [ "$DEPTH" -lt 15 ]; do
        local NAME
        NAME=$(ps -p "$PID" -o comm= 2>/dev/null)
        if echo "$NAME" | grep -qi "alacritty"; then
          TERM_APP="Alacritty"; break
        elif echo "$NAME" | grep -qi "electron\|code"; then
          TERM_APP="Code"; break
        elif echo "$NAME" | grep -qi "goland"; then
          TERM_APP="GoLand"; break
        elif echo "$NAME" | grep -qi "iterm\|wezterm\|kitty"; then
          TERM_APP="$NAME"; break
        fi
        PID=$(ps -p "$PID" -o ppid= 2>/dev/null | tr -d ' ')
        DEPTH=$((DEPTH + 1))
      done
    fi
  fi

  TERM_APP="${TERM_APP:-Alacritty}"

  # Check expected workspace first (fast path based on aerospace rules)
  local EXPECTED_WS
  case "$TERM_APP" in
    Alacritty)      EXPECTED_WS="M" ;;
    Code|GoLand)    EXPECTED_WS="C" ;;
    *)              EXPECTED_WS="M" ;;
  esac

  if aerospace list-windows --workspace "$EXPECTED_WS" 2>/dev/null | grep -qi "$TERM_APP"; then
    echo "$EXPECTED_WS"
    return
  fi

  # Fallback: search all workspaces
  for ws in M B N S C D T Z I A; do
    if aerospace list-windows --workspace "$ws" 2>/dev/null | grep -qi "$TERM_APP"; then
      echo "$ws"
      return
    fi
  done

  echo "$EXPECTED_WS"
}

WORKSPACE=$(detect_workspace)
TIMESTAMP=$(date +%s)

# --- Update state file ---
[ ! -f "$STATE_FILE" ] && echo '[]' > "$STATE_FILE"

ENTRY=$(jq -n \
  --arg s "$TMUX_SESSION" \
  --arg w "$WORKSPACE" \
  --argjson t "$TIMESTAMP" \
  '{session: $s, workspace: $w, ts: $t}')

# Replace any existing notification for this session, then append
jq --arg s "$TMUX_SESSION" '[.[] | select(.session != $s)]' "$STATE_FILE" 2>/dev/null | \
  jq --argjson e "$ENTRY" '. + [$e]' > "${STATE_FILE}.tmp" && \
  mv "${STATE_FILE}.tmp" "$STATE_FILE"

# --- Play notification sound (unless muted) ---
MUTE_FILE="/tmp/claude-notify-muted"
if [ ! -f "$MUTE_FILE" ]; then
  afplay /System/Library/Sounds/Glass.aiff &
fi

# --- Trigger sketchybar ---
sketchybar --trigger claude_notification 2>/dev/null

exit 0
