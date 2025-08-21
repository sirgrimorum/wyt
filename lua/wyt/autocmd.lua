local api = vim.api
local project = require("wyt.project")
local loc = require("wyt.localization")
local idea = require("wyt.idea")

local M = {}



function M.setup()
    -- ToDo: Define if we want to use it after a write
    -- api.nvim_create_autocmd("BufWritePost", {
    --     pattern = "plan.wyt.md",
    --     callback = idea.sync_group_ideas_to_ideas,
    --     desc = loc.t("sync_group_ideas_desc")
    -- })

    api.nvim_create_autocmd("BufEnter", {
        pattern = "plan.wyt.md",
        callback = function()
            if not project.setup() then return end
            local lang = project.lang
            loc.set_lang(lang)
            print(loc.t("current_lang") .. lang)
        end,
        desc = loc.t("set_lang_on_enter")
    })
    api.nvim_create_autocmd("InsertLeave", {
        pattern = "*plan.wyt.md",
        callback = idea.sync_group_ideas_to_ideas,
        desc = loc.t("sync_group_ideas_desc")
    })
end

return M
