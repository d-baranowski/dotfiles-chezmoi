local M = {}

function M.setup(opts)
  local config = require("cbridge.config")
  config.setup(opts)

  local mirror = require("cbridge.mirror")
  mirror.attach()

  local cb = require("cbridge.cb")
  local pickers = require("cbridge.pickers")

  vim.api.nvim_create_user_command("CbHistory", function(cmd)
    local reg = cmd.args ~= "" and cmd.args or nil
    pickers.history(reg)
  end, { nargs = "?", desc = "Browse clipboard history" })

  vim.api.nvim_create_user_command("CbRegisters", function()
    pickers.registers()
  end, { desc = "Browse cb named registers" })

  vim.api.nvim_create_user_command("CbPush", function(cmd)
    local reg = cmd.args
    if reg == "" then
      vim.notify("Usage: :CbPush <register>", vim.log.levels.ERROR)
      return
    end
    local content = vim.fn.getreg(reg)
    if content == "" then
      vim.notify("Register " .. reg .. " is empty", vim.log.levels.WARN)
      return
    end
    cb.copy_to_register(reg, content)
    vim.notify("Pushed \"" .. reg .. " -> cb_" .. reg)
  end, { nargs = 1, desc = "Push vim register to cb" })

  vim.api.nvim_create_user_command("CbPull", function(cmd)
    local reg = cmd.args
    if reg == "" then
      vim.notify("Usage: :CbPull <register>", vim.log.levels.ERROR)
      return
    end
    local content = cb.paste_from_register(reg)
    if not content or content == "" then
      vim.notify("cb_" .. reg .. " is empty", vim.log.levels.WARN)
      return
    end
    vim.fn.setreg(reg, content)
    vim.notify("Pulled cb_" .. reg .. " -> \"" .. reg)
  end, { nargs = 1, desc = "Pull cb register into vim" })

  vim.api.nvim_create_user_command("CbSync", function()
    local regs = config.options.auto_mirror.registers
    local pushed, pulled = 0, 0
    for letter in regs:gmatch(".") do
      local vim_content = vim.fn.getreg(letter)
      local cb_content = cb.paste_from_register(letter)
      if vim_content ~= "" and (not cb_content or cb_content == "") then
        cb.copy_to_register(letter, vim_content)
        pushed = pushed + 1
      elseif (not vim_content or vim_content == "") and cb_content and cb_content ~= "" then
        vim.fn.setreg(letter, cb_content)
        pulled = pulled + 1
      end
    end
    vim.notify(string.format("Sync: pushed %d, pulled %d", pushed, pulled))
  end, { desc = "Bidirectional sync vim <-> cb registers" })

  vim.api.nvim_create_user_command("CbWatch", function(cmd)
    if cmd.args == "on" then
      config.options.auto_mirror.enabled = true
      vim.notify("cbridge auto-mirror enabled")
    elseif cmd.args == "off" then
      config.options.auto_mirror.enabled = false
      vim.notify("cbridge auto-mirror disabled")
    else
      vim.notify("Auto-mirror: " .. (config.options.auto_mirror.enabled and "on" or "off"))
    end
  end, { nargs = "?", desc = "Toggle auto-mirror" })
end

function M.servername()
  return vim.v.servername
end

return M
