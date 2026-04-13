local M = {}
local config = require("clipboard.config")

local function runCb(args)
  local cmd = config.cbPath .. " " .. args .. " 2>/dev/null"
  local handle = io.popen(cmd)
  if not handle then return nil end
  local result = handle:read("*a")
  handle:close()
  return result
end

local function parseHistory()
  local raw = runCb("history")
  if not raw or raw == "" then return {} end

  local ok, parsed = pcall(hs.json.decode, raw)
  if not ok or not parsed then return {} end

  -- cb history returns {"0": {"date":..., "content":...}, "1": ...}
  -- collect entries, sort by key (most recent first)
  local entries = {}
  for key, entry in pairs(parsed) do
    if entry.content and type(entry.content) == "string" then
      table.insert(entries, { idx = tonumber(key) or 0, content = entry.content })
    end
  end
  table.sort(entries, function(a, b) return a.idx < b.idx end)

  local choices = {}
  for _, entry in ipairs(entries) do
    local preview = entry.content:sub(1, config.maxPreviewChars)
    if #entry.content > config.maxPreviewChars then preview = preview .. "..." end
    table.insert(choices, {
      text = preview:gsub("\n", " "),
      subText = string.format("%d chars", #entry.content),
      fullText = entry.content,
    })
  end
  return choices
end

function M.showHistory()
  local choices = parseHistory()
  if #choices == 0 then
    hs.alert.show("Clipboard history is empty")
    return
  end

  local chooser = hs.chooser.new(function(choice)
    if not choice then return end
    hs.pasteboard.setContents(choice.fullText)
  end)
  chooser:choices(choices)
  chooser:searchSubText(true)
  chooser:show()
end

function M.showRegisters()
  local choices = {}
  for letter in ("abcdefghijklmnopqrstuvwxyz"):gmatch(".") do
    local content = runCb("paste_" .. letter)
    if content and content ~= "" then
      local preview = content:sub(1, config.maxPreviewChars)
      table.insert(choices, {
        text = "cb_" .. letter,
        subText = preview:gsub("\n", " "),
        fullText = content,
      })
    end
  end

  if #choices == 0 then
    hs.alert.show("No named registers populated")
    return
  end

  local chooser = hs.chooser.new(function(choice)
    if not choice then return end
    hs.pasteboard.setContents(choice.fullText)
  end)
  chooser:choices(choices)
  chooser:searchSubText(true)
  chooser:show()
end

return M
