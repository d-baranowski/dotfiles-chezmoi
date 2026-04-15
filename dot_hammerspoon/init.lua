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

-- Keybindings cheatsheet: fuzzy-searchable picker
local ok2, err2 = pcall(function()
  keybindings = require("keybindings")
end)
if not ok2 then
  hs.alert.show("Keybindings module error: " .. tostring(err2))
  print("Keybindings module error: " .. tostring(err2))
end

-- Aerospace window picker (invoked from Leader Key via `leader k`)
local ok3, err3 = pcall(function()
  workspaces = require("workspaces")
end)
if not ok3 then
  hs.alert.show("Workspaces module error: " .. tostring(err3))
  print("Workspaces module error: " .. tostring(err3))
end

-- ratelimit: persistent red banners for API rate-limit alerts.
-- Invoked by slackdump-sync via `hs -c 'ratelimit.show(...)'`.
-- Dismissed globally via ⌘⇧⎋.
local ok4, err4 = pcall(function()
  ratelimit = require("ratelimit")
end)
if not ok4 then
  hs.alert.show("Ratelimit module error: " .. tostring(err4))
  print("Ratelimit module error: " .. tostring(err4))
end

-- shift+f6 → go to most recent Claude notification (same as bell click)
hs.hotkey.bind({"shift"}, "f6", function()
  hs.task.new(os.getenv("HOME") .. "/.config/sketchybar/plugins/claude_notify_goto.sh", nil):start()
end)

-- Enable IPC so `hs` CLI and Leader Key can call into Hammerspoon
-- Must be loaded after all other modules; survives reloads
require("hs.ipc")

hs.alert.show("Hammerspoon config loaded")
