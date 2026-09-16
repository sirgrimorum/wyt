-- O1: only loc needed at top (for desc strings); all heavy modules required lazily
local loc = require("wyt.localization")

local M = {}

local function handle_move(direction)
    local buf = vim.api.nvim_get_current_buf()
    local cursor = vim.api.nvim_win_get_cursor(0)[1]
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local line = lines[cursor]
    if not line then return end

    local group_pat = "^## " .. require("wyt.project").t("group_tag") .. ": "
    if line:match(group_pat) then
        require("wyt.group").move_group(direction)
    elseif line:match("^%- ") then
        require("wyt.idea").move_idea(direction)
    end
end

-- F8: buffer-local keymaps: called from autocmd.lua on BufEnter plan.wyt.md
-- Keeps keys scoped to wyt buffers only; does not pollute all buffers in the session
function M.setup_buf(buf)
    vim.keymap.set("n", "<S-Up>", function() handle_move("up") end, {
        buffer = buf,
        desc = loc.t("move_idea_up") .. " / Mover grupo arriba",
    })
    vim.keymap.set("n", "<S-Down>", function() handle_move("down") end, {
        buffer = buf,
        desc = loc.t("move_idea_down") .. " / Mover grupo abajo",
    })
    vim.keymap.set("n", "<S-Tab>", function()
        require("wyt.plan").goto_wyt_tab()
    end, {
        buffer = buf,
        desc = loc.t("nav_tab_desc"),
    })
end

-- P15: buffer-local keymaps for text.wyt.md placeholder expansion
function M.setup_text_buf(buf)
    vim.keymap.set("n", "<leader>we", function()
        require("wyt.text").expand_at_cursor()
    end, { buffer = buf, desc = loc.t("expand_desc") })
    vim.keymap.set("n", "]w", function()
        require("wyt.text").expand_next()
    end, { buffer = buf, desc = loc.t("no_placeholder_below"):gsub("%[WYT%] ", "") })
    vim.keymap.set("n", "[w", function()
        require("wyt.text").expand_prev()
    end, { buffer = buf, desc = loc.t("no_placeholder_above"):gsub("%[WYT%] ", "") })
end

function M.setup()
    -- F8: keymaps are now buffer-local, registered from autocmd.lua via setup_buf()
    -- Nothing to do here; kept for API compatibility
end

return M
