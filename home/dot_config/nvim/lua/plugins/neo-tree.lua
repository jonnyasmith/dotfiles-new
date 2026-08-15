---@type LazySpec
return {
  "nvim-neo-tree/neo-tree.nvim",
  -- AstroNvim's opts function force-merges its defaults *over* user tables,
  -- so this must be a function to land after it.
  opts = function(_, opts)
    opts.filesystem.filtered_items.visible = true -- start with hidden files shown; `H` still toggles
  end,
}
