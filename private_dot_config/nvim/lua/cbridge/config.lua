local M = {}

M.defaults = {
  cb_path = "cb",
  auto_mirror = {
    enabled = true,
    registers = "abcdefghijklmnopqrstuvwxyz",
    exclude_unnamed = true,
    debounce_ms = 100,
  },
  picker = "auto",
  on_pull_conflict = "prompt",
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

return M
