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

-- stopwatch: small bottom-right overlay, driven by Leader Key (group "x")
local ok5, err5 = pcall(function()
  stopwatch = require("stopwatch")
end)
if not ok5 then
  hs.alert.show("Stopwatch module error: " .. tostring(err5))
  print("Stopwatch module error: " .. tostring(err5))
end

-- calendar: important-calendar picker + upcoming-events popups.
-- Watcher polls Calendar.app every 60s and alerts at 15/5/1 min before each
-- event on a selected-important calendar.
local ok6, err6 = pcall(function()
  calendar = require("calendar")
  calendar.startWatcher()
end)
if not ok6 then
  hs.alert.show("Calendar module error: " .. tostring(err6))
  print("Calendar module error: " .. tostring(err6))
end

-- pass(1) integration: secret copy (concealed, no history) + add, under
-- Leader Key group "c → P".
local ok7, err7 = pcall(function()
  pass = require("pass")
end)
if not ok7 then
  hs.alert.show("Pass module error: " .. tostring(err7))
  print("Pass module error: " .. tostring(err7))
end

-- ask_haiku: floating one-shot Claude Haiku prompt window, triggered from
-- Leader Key root "h". Uses `claude -p --model haiku` (subscription auth).
local ok8, err8 = pcall(function()
  ask_haiku = require("ask_haiku")
end)
if not ok8 then
  hs.alert.show("Ask Haiku module error: " .. tostring(err8))
  print("Ask Haiku module error: " .. tostring(err8))
end

-- slacksync: webview UI to browse/queue/sync Slack chats (replacement for the
-- disabled hourly auto-sync; only hits Slack when user presses "Run Queue").
-- Invoked from Leader Key root "S" via `hs -c 'slacksync.show()'`.
local ok9, err9 = pcall(function()
  slacksync = require("slacksync")
end)
if not ok9 then
  hs.alert.show("Slacksync module error: " .. tostring(err9))
  print("Slacksync module error: " .. tostring(err9))
end

-- pr_notify: poll authored PRs every 2 min and overlay-alert on reviews,
-- comments, approvals, and CI failures. Backed by ~/.local/bin/gh-pr-notify.
--
-- Auto-polling disabled 2026-09-08: not actively working a repo, and the
-- 2-min timer was respawning gh-pr-notify around the clock. The module is
-- still REQUIRED, not commented out, because Leader Key binds
-- pr_notify.showUpcoming() / toggleWatcher() / checkNow() — commenting the
-- require would leave those three bindings calling into a nil global.
-- So: load the module, just don't start the timer. `toggleWatcher()` from
-- Leader Key still turns polling back on for a session; to restore it at
-- startup, uncomment the startWatcher() line.
local okPR, errPR = pcall(function()
  pr_notify = require("pr_notify")
  -- pr_notify.startWatcher()
end)
if not okPR then
  hs.alert.show("PR notify module error: " .. tostring(errPR))
  print("PR notify module error: " .. tostring(errPR))
end

-- shift+f6 → go to most recent Claude notification (same as bell click)
hs.hotkey.bind({"shift"}, "f6", function()
  hs.task.new(os.getenv("HOME") .. "/.config/sketchybar/plugins/claude_notify_goto.sh", nil):start()
end)

-- Enable IPC so `hs` CLI and Leader Key can call into Hammerspoon
-- Must be loaded after all other modules; survives reloads
require("hs.ipc")

hs.alert.show("Hammerspoon config loaded")
