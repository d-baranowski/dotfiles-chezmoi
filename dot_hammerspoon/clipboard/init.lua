local M = {}

M.config = require("clipboard.config")
M.watcher = require("clipboard.watcher")
M.picker = require("clipboard.picker")
M.nvim = require("clipboard.nvim")

function M.start()
  M.watcher.start()

  hs.hotkey.bind({ "cmd", "alt" }, "v", function()
    M.picker.showHistory()
  end)

  hs.hotkey.bind({ "cmd", "alt", "shift" }, "v", function()
    M.picker.showRegisters()
  end)
end

function M.stop()
  M.watcher.stop()
end

function M.yankSelectionTo(letter)
  hs.eventtap.keyStroke({ "cmd" }, "c")
  hs.timer.doAfter(0.1, function()
    local content = hs.pasteboard.getContents()
    if not content then return end
    local task = hs.task.new(M.config.cbPath, nil, function() return true end,
      { "copy_" .. letter, content })
    task:start()
  end)
end

function M.pasteRegister(letter)
  local handle = io.popen(M.config.cbPath .. " paste_" .. letter .. " 2>/dev/null")
  if not handle then return end
  local content = handle:read("*a")
  handle:close()
  if not content or content == "" then return end
  hs.pasteboard.setContents(content)
  hs.timer.doAfter(0.05, function()
    hs.eventtap.keyStroke({ "cmd" }, "v")
  end)
end

return M
