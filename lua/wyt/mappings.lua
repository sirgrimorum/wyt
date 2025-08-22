local api = vim.api
local project = require("wyt.project")
local idea = require("wyt.idea")
local group = require("wyt.group")
local plan = require("wyt.plan")
local loc = require("wyt.localization")

local M = {}

local function handle_move(direction)
    local buf = api.nvim_get_current_buf()
    local filename = api.nvim_buf_get_name(buf)
    if not filename:match("plan%.wyt%.md$") then return end

    local cursor = api.nvim_win_get_cursor(0)[1]
    local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
    local line = lines[cursor]
    if not line then return end

    local group_pat = "^## " .. project.t("group_tag") .. ": "
    if line:match(group_pat) then
        if direction == "up" then group.move_group("up") else group.move_group("down") end
    elseif line:match("^%- ") then
        if direction == "up" then idea.move_idea("up") else idea.move_idea("down") end
    end
end

function M.setup()
    vim.keymap.set("n", "<S-Up>", function() handle_move("up") end, {desc = loc.t("move_idea_up") .. " / Mover grupo arriba"})
    vim.keymap.set("n", "<S-Down>", function() handle_move("down") end, {desc = loc.t("move_idea_down") .. " / Mover grupo abajo"})
    vim.keymap.set("n", "<S-Tab>", plan.goto_wyt_tab, {desc = loc.t("nav_tab_desc")})
end

return M