return {
  "nvim-treesitter/nvim-treesitter",
  build = ":TSUpdate",
  event = { "BufReadPre", "BufNewFile" },
  main = "nvim-treesitter",
  opts = {
    ensure_installed = { "python", "rust", "lua", "nix", "json", "yaml", "toml", "markdown" },
    highlight = { enable = true },
    indent = { enable = true },
  },
}
