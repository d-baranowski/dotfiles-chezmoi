return {
  {
    dir = vim.fn.stdpath("config") .. "/lua/cbridge",
    name = "cbridge.nvim",
    event = "VeryLazy",
    config = function()
      require("cbridge").setup({
        cb_path = "cb",
        auto_mirror = {
          enabled = true,
          registers = "abcdefghijklmnopqrstuvwxyz",
          exclude_unnamed = true,
          debounce_ms = 100,
        },
        picker = "auto",
      })
    end,
    keys = {
      { "<leader>ch", "<cmd>CbHistory<cr>", desc = "Clipboard history" },
      { "<leader>cr", "<cmd>CbRegisters<cr>", desc = "Clipboard registers" },
    },
  },
}
