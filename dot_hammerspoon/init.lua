-- Hammerspoon configuration
-- https://www.hammerspoon.org/

-- Reload config automatically when this file changes (requires ReloadConfiguration spoon)
if pcall(hs.loadSpoon, "ReloadConfiguration") then
  spoon.ReloadConfiguration:start()
end

-- Clipboard system: capture, picker, registers
local clipboard = require("clipboard")
clipboard.start()

hs.alert.show("Hammerspoon config loaded")
