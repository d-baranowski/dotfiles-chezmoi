local M = {}
local config = require("cbridge.config")

function M.copy_to_register(letter, content)
  vim.system({ config.options.cb_path, "copy_" .. letter }, { stdin = content })
end

function M.paste_from_register(letter)
  local result = vim.system({ config.options.cb_path, "paste_" .. letter }, { text = true }):wait()
  if result.code ~= 0 then return nil end
  return result.stdout
end

function M.history()
  local result = vim.system({ config.options.cb_path, "history" }, { text = true }):wait()
  if result.code ~= 0 then return {} end
  local ok, parsed = pcall(vim.json.decode, result.stdout)
  if not ok or not parsed then return {} end

  -- cb history returns {"0": {...}, "1": {...}} — convert to sorted list
  local entries = {}
  for key, entry in pairs(parsed) do
    if entry.content and type(entry.content) == "string" then
      table.insert(entries, { idx = tonumber(key) or 0, content = entry.content })
    end
  end
  table.sort(entries, function(a, b) return a.idx < b.idx end)
  return entries
end

return M
