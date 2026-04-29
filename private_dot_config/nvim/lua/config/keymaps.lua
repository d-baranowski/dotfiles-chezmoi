-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
vim.api.nvim_set_keymap("i", "jj", "<Esc>", { noremap = false })
vim.api.nvim_set_keymap("i", "jk", "<Esc>", { noremap = false })
vim.keymap.set("n", "<S-q>", "<cmd>Neotree focus<cr>", { desc = "File explorer" })

-- Jump list navigation (like VS Code's go back/forward)
vim.keymap.set("n", "gb", "<C-o>", { desc = "Jump back" })
vim.keymap.set("n", "gn", "<C-i>", { desc = "Jump forward" })

-- Reload config
vim.keymap.set("n", "<leader>sr", function()
  dofile(vim.env.MYVIMRC)
  vim.notify("Config reloaded")
end, { desc = "Reload config" })

-- Toggle "raw" mode for Go: strip everything except syntax highlighting.
-- Disables gopls, diagnostics, inlay hints, completion, and Copilot for all
-- current and future Go buffers. Treesitter/syntax highlighting is untouched.
local go_raw_group = vim.api.nvim_create_augroup("GoRawMode", { clear = true })
vim.g.go_raw_mode = false

local function apply_raw_to_buf(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  if vim.bo[buf].filetype ~= "go" then return end
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
    vim.lsp.buf_detach_client(buf, client.id)
  end
  vim.diagnostic.enable(false, { bufnr = buf })
  pcall(vim.lsp.inlay_hint.enable, false, { bufnr = buf })
  vim.b[buf].completion = false       -- LazyVim blink.cmp honors this
  vim.b[buf].copilot_enabled = false  -- Copilot honors this
end

local function toggle_go_raw()
  vim.g.go_raw_mode = not vim.g.go_raw_mode
  if vim.g.go_raw_mode then
    -- Stop gopls entirely so it doesn't re-attach
    for _, client in ipairs(vim.lsp.get_clients({ name = "gopls" })) do
      vim.lsp.stop_client(client.id, true)
    end
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      apply_raw_to_buf(buf)
    end
    vim.api.nvim_create_autocmd("FileType", {
      group = go_raw_group,
      pattern = "go",
      callback = function(ev) apply_raw_to_buf(ev.buf) end,
    })
    vim.notify("Go raw mode: ON — syntax only")
  else
    vim.api.nvim_clear_autocmds({ group = go_raw_group })
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == "go" then
        vim.diagnostic.enable(true, { bufnr = buf })
        vim.b[buf].completion = nil
        vim.b[buf].copilot_enabled = nil
      end
    end
    vim.notify("Go raw mode: OFF — reopen Go files to re-attach gopls")
  end
end

vim.keymap.set("n", "<leader>uG", toggle_go_raw, { desc = "Toggle Go raw mode (syntax only)" })
