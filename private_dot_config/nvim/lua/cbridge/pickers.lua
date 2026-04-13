local M = {}
local config = require("cbridge.config")
local cb = require("cbridge.cb")

local function get_picker()
  local setting = config.options.picker
  if setting ~= "auto" then return setting end
  if pcall(require, "fzf-lua") then return "fzf-lua" end
  if pcall(require, "telescope") then return "telescope" end
  if pcall(require, "snacks") then return "snacks" end
  return "vim.ui.select"
end

local function pick_and_act(items, opts, on_choice)
  local picker = get_picker()

  if picker == "fzf-lua" then
    local fzf = require("fzf-lua")
    fzf.fzf_exec(
      vim.tbl_map(function(item) return item.display end, items),
      {
        prompt = opts.prompt or "> ",
        actions = {
          ["default"] = function(selected)
            if not selected or #selected == 0 then return end
            for _, item in ipairs(items) do
              if item.display == selected[1] then
                on_choice(item)
                return
              end
            end
          end,
        },
      }
    )
  elseif picker == "telescope" then
    local pickers_mod = require("telescope.pickers")
    local finders = require("telescope.finders")
    local conf = require("telescope.config").values
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")

    pickers_mod.new({}, {
      prompt_title = opts.prompt or "Select",
      finder = finders.new_table({
        results = items,
        entry_maker = function(item)
          return { value = item, display = item.display, ordinal = item.display }
        end,
      }),
      sorter = conf.generic_sorter({}),
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if selection then on_choice(selection.value) end
        end)
        return true
      end,
    }):find()
  else
    vim.ui.select(items, {
      prompt = opts.prompt or "Select: ",
      format_item = function(item) return item.display end,
    }, function(item)
      if item then on_choice(item) end
    end)
  end
end

function M.history(target_reg)
  local entries = cb.history()
  if #entries == 0 then
    vim.notify("Clipboard history is empty", vim.log.levels.INFO)
    return
  end

  local items = {}
  for _, entry in ipairs(entries) do
    local preview = entry.content:sub(1, 80):gsub("\n", " ")
    table.insert(items, { display = preview, content = entry.content })
  end

  pick_and_act(items, { prompt = "Clipboard History> " }, function(item)
    if target_reg then
      vim.fn.setreg(target_reg, item.content)
      vim.notify("Set register " .. target_reg)
    else
      vim.api.nvim_put(vim.split(item.content, "\n"), "", true, true)
    end
  end)
end

function M.registers()
  local items = {}
  for letter in ("abcdefghijklmnopqrstuvwxyz"):gmatch(".") do
    local content = cb.paste_from_register(letter)
    if content and content ~= "" then
      local preview = content:sub(1, 80):gsub("\n", " ")
      table.insert(items, {
        display = "cb_" .. letter .. ": " .. preview,
        letter = letter,
        content = content,
      })
    end
  end

  if #items == 0 then
    vim.notify("No named registers populated", vim.log.levels.INFO)
    return
  end

  pick_and_act(items, { prompt = "cb Registers> " }, function(item)
    vim.api.nvim_put(vim.split(item.content, "\n"), "", true, true)
  end)
end

return M
