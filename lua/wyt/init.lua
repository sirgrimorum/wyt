local commands = require("wyt.commands")
local autocmd = require("wyt.autocmd")
local mappings = require("wyt.mappings")

local M = {}

function M.setup(opts)
    if not pcall(require, "telescope") then
        -- print("[WYT] Warning: telescope.nvim is required for multi-selection.\n")
    end
    commands.setup()
    autocmd.setup()
    mappings.setup()
end

return M
