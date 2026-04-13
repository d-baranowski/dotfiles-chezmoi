-- Hammerspoon configuration
-- https://www.hammerspoon.org/

-- Clipboard system: capture, picker, registers
local ok, err = pcall(function()
  clipboard = require("clipboard")
  clipboard.start()
end)
if not ok then
  hs.alert.show("Clipboard module error: " .. tostring(err))
  print("Clipboard module error: " .. tostring(err))
end

-- shift+f6 → go to most recent Claude notification (same as bell click)
hs.hotkey.bind({"shift"}, "f6", function()
  hs.task.new(os.getenv("HOME") .. "/.config/sketchybar/plugins/claude_notify_goto.sh", nil):start()
end)

-- Enable IPC so `hs` CLI and Leader Key can call into Hammerspoon
-- Must be loaded after all other modules; survives reloads
require("hs.ipc")

hs.alert.show("Hammerspoon config loaded")
