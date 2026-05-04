return {
  "nvim-neo-tree/neo-tree.nvim",
  opts = {
    filesystem = {
      filtered_items = {
        visible = true,
        hide_dotfiles = false,
        hide_gitignored = false,
      },
    },
    window = {
      mappings = {
        ["s"] = "noop",
        ["S"] = "noop",
        ["|"] = "open_vsplit",
        ["-"] = "open_split",
      },
    },
  },
  config = function(_, opts)
    require("neo-tree").setup(opts)
    vim.api.nvim_create_autocmd("FileType", {
      pattern = "neo-tree",
      callback = function(ev)
        vim.keymap.set("n", "s", "V", { buffer = ev.buf, desc = "Start visual selection" })
      end,
    })
  end,
}
