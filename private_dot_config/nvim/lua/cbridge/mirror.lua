local M = {}
local config = require("cbridge.config")
local cb = require("cbridge.cb")

local last_mirror = {}

function M.on_yank()
  if not config.options.auto_mirror.enabled then return end

  local event = vim.v.event
  local regname = event.regname

  if regname == "" and config.options.auto_mirror.exclude_unnamed then return end
  if not config.options.auto_mirror.registers:find(regname, 1, true) then return end

  local now = vim.uv.now()
  if last_mirror[regname] and (now - last_mirror[regname]) < config.options.auto_mirror.debounce_ms then
    return
  end
  last_mirror[regname] = now

  local content = table.concat(event.regcontents, "\n")
  cb.copy_to_register(regname, content)
end

function M.attach()
  vim.api.nvim_create_autocmd("TextYankPost", {
    group = vim.api.nvim_create_augroup("cbridge_mirror", { clear = true }),
    callback = M.on_yank,
  })
end

return M
