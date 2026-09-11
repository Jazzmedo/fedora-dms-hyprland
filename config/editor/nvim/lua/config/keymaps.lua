-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
-- -- Run the current cell (similar to Shift+Enter)
vim.keymap.set("n", "<S-Enter>", ":MoltenEvaluateOperator<CR>", { desc = "Run current cell" })

-- Visual select a block of code and run it
vim.keymap.set("v", "<S-Enter>", ":<C-u>MoltenEvaluateVisual<CR>", { desc = "Run visual selection" })

-- Clear the output window of the current cell
vim.keymap.set("n", "<leader>mc", ":MoltenDelete<CR>", { desc = "Clear cell output" })

-- Show/Hide cell output window
vim.keymap.set("n", "<leader>mo", ":MoltenShowOutput<CR>", { desc = "Show cell output" })
