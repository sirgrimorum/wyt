local commands = require("wyt.commands")
local autocmd = require("wyt.autocmd")

local M = {}

function M.setup(opts)
    commands.setup()
    autocmd.setup()
end

return M
