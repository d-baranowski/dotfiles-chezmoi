#!/bin/bash
# Dismiss all visible macOS notifications by walking the Notification Center
# UI via System Events. Requires Accessibility permission for whatever app
# runs this (Leader Key already has it since it sends keystrokes).

/usr/bin/osascript <<'EOF'
tell application "System Events"
  tell process "NotificationCenter"
    -- Loop because clearing one notification can reveal another underneath
    -- (stacked groups), and some Clear All actions only collapse one level.
    repeat 10 times
      set _cleared to false
      try
        set _windows to every window
      on error
        exit repeat
      end try
      if (count of _windows) is 0 then exit repeat

      repeat with _w in _windows
        try
          -- Walk every UI element in the window and look for groups that
          -- expose a "Clear All" or "Close" action. The exact nesting
          -- (window → group → group → scroll area → group → notification)
          -- shifts between macOS versions, so we recurse via "entire contents".
          set _elems to entire contents of _w
          repeat with _e in _elems
            try
              perform (first action of _e whose description is "Clear All")
              set _cleared to true
            end try
            try
              perform (first action of _e whose description is "Close")
              set _cleared to true
            end try
          end repeat
        end try
      end repeat

      if not _cleared then exit repeat
      delay 0.1
    end repeat
  end tell
end tell
EOF
