#!/bin/bash
# Toggle the system input (microphone) volume between 0 and 100.
# Bound to Leader Key for a global mic mute shortcut.

osascript <<'EOF'
set v to input volume of (get volume settings)
if v > 0 then
  set volume input volume 0
  display notification "Microphone muted" with title "Mic"
else
  set volume input volume 100
  display notification "Microphone on" with title "Mic"
end if
EOF
