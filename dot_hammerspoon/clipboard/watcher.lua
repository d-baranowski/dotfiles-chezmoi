local M = {}
local config = require("clipboard.config")

local lastSeen = nil
local watcher = nil

local function captureToClipboard()
  local frontApp = hs.application.frontmostApplication()
  if frontApp then
    for _, excluded in ipairs(config.excludedApps) do
      if frontApp:name() == excluded then return end
    end
  end

  local types = hs.pasteboard.pasteboardTypes()
  if types then
    for _, t in ipairs(types) do
      if t == "org.nspasteboard.ConcealedType" then return end
    end
  end

  local contents = hs.pasteboard.getContents()
  if not contents or contents == "" then return end
  if contents == lastSeen then return end
  lastSeen = contents

  local task = hs.task.new(config.cbPath, nil, function() return true end, { "copy" })
  task:setInput(contents)
  task:start()
end

function M.start()
  watcher = hs.pasteboard.watcher.new(captureToClipboard)
  watcher:start()
end

function M.stop()
  if watcher then watcher:stop(); watcher = nil end
end

return M
