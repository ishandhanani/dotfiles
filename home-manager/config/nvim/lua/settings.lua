local opt = vim.opt

opt.number = true
opt.syntax = "on"
opt.clipboard = "unnamedplus"
opt.tabstop = 4
opt.shiftwidth = 4
opt.expandtab = true
opt.smartindent = true
opt.termguicolors = true
opt.signcolumn = "yes"
opt.updatetime = 300
opt.scrolloff = 8
opt.wrap = false

-- Format on save via LSP (ruff for Python, rust-analyzer for Rust)
vim.api.nvim_create_autocmd("BufWritePre", {
  callback = function()
    vim.lsp.buf.format({ async = false })
  end,
})
