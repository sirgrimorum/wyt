-- Minimal Neovim init for running tests without a full user config.
-- Usage: nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/"
--    or: nvim -l tests/minimal_init.lua tests/some_spec.lua

vim.opt.runtimepath:prepend(vim.fn.getcwd())  -- add plugin root to rtp

-- Bootstrap plenary if available (used for test runner)
local ok = pcall(require, "plenary")
if not ok then
    vim.notify("plenary.nvim not found — install it to run tests", vim.log.levels.ERROR)
end
