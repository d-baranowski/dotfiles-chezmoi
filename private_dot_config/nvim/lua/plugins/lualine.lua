return {
  "nvim-lualine/lualine.nvim",
  opts = function(_, opts)
    table.insert(opts.sections.lualine_x, 1, {
      function()
        return "Leader: Space | S-h prev buf | S-l next buf"
      end,
      color = { fg = "#7aa2f7" },
    })
  end,
}
