-- Set leader before anything else (required by lazy.nvim)
vim.g.mapleader = " "

-- Bootstrap lazy.nvim
local lazydir = vim.fn.stdpath("data") .. "/lazy"
local lazypath = lazydir .. "/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.mkdir(lazydir, "p")
  local result = vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })

  if vim.v.shell_error ~= 0 then
    error("Failed to install lazy.nvim:\n" .. result)
  end
end
vim.opt.rtp:prepend(lazypath)

require("settings")
require("keymaps")

require("lazy").setup("plugins")

-- LSP servers (native vim.lsp.config, no plugin needed)
vim.lsp.config("ty", {
  cmd = { "ty", "server" },
  filetypes = { "python" },
  root_markers = { "pyproject.toml", "setup.py", ".git" },
})

vim.lsp.config("ruff", {
  cmd = { "ruff", "server" },
  filetypes = { "python" },
  root_markers = { "pyproject.toml", "ruff.toml", ".ruff.toml", ".git" },
})

vim.lsp.config("rust_analyzer", {
  cmd = { "rust-analyzer" },
  filetypes = { "rust" },
  root_markers = { "Cargo.toml", ".git" },
})

vim.lsp.enable({ "ty", "ruff", "rust_analyzer" })
