vim.g.mapleader = " "

local map = vim.keymap.set

-- LSP bindings (matching vim muscle memory)
map("n", "gr", vim.lsp.buf.references, { desc = "References" })
map("n", "gn", vim.lsp.buf.rename, { desc = "Rename" })
map("n", "gi", vim.lsp.buf.implementation, { desc = "Implementation" })
map("n", "K", vim.lsp.buf.hover, { desc = "Hover" })
map("n", "gm", vim.diagnostic.goto_next, { desc = "Next diagnostic" })
map("n", "gd", vim.lsp.buf.definition, { desc = "Go to definition" })
map("n", "ga", vim.lsp.buf.code_action, { desc = "Code action" })

-- Telescope
map("n", "<leader>ff", "<cmd>Telescope find_files<cr>", { desc = "Find files" })
map("n", "<leader>rg", "<cmd>Telescope live_grep<cr>", { desc = "Live grep" })
map("n", "<leader>fb", "<cmd>Telescope buffers<cr>", { desc = "Buffers" })
