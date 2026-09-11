-- Minimal Neovim init for loading the plugin without a user config.
--
-- The suite does not use this file: `tests/runner.lua` puts the plugin on the
-- runtimepath itself, so one command runs everything. Keep this for poking at
-- the plugin by hand:
--
--   nvim -u tests/minimal_init.lua
--
-- plenary.nvim is deliberately not a dependency. It used to be what ran the
-- tests, and `PlenaryBustedDirectory` hangs forever when it is not installed,
-- which is the whole reason the suite ships its own runner.

vim.opt.runtimepath:prepend(vim.fn.getcwd())
require("wyt").setup({})
