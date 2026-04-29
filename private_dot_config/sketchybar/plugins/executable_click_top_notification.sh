#!/bin/bash
# Perform the default "click" action on the topmost visible macOS notification
# (as if the user clicked the notification body — opens the sending app or its
# deep link target). Requires Accessibility permission for whatever app runs
# this; Leader Key already has it since it sends keystrokes.
#
# Companion to clear_notifications.sh — that one dismisses, this one activates.

/usr/bin/osascript <<'EOF'
tell application "System Events"
  tell process "NotificationCenter"
    try
      set _wins to every window
    on error
      return "no NC windows"
    end try
    if (count of _wins) is 0 then return "no notifications"

    -- Notification Center's AX tree lists notification groups in visual order
    -- (top first). Each notification exposes actions: press, Show Details,
    -- Reply, Close. "press" is the default-click action.
    repeat with _w in _wins
      try
        set _elems to entire contents of _w
        repeat with _e in _elems
          try
            perform (first action of _e whose description is "press")
            return "pressed"
          end try
        end repeat
      end try
    end repeat
    return "no pressable notification found"
  end tell
end tell
EOF
