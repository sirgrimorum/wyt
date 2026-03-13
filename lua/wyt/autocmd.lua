local api = vim.api
local loc = require("wyt.localization")

local M = {}

-- O3: debounce timer — sync fires 300ms after the last keystroke, not on every change
local _sync_timer = nil
local function debounced_sync()
    if _sync_timer then
        _sync_timer:stop()
        _sync_timer:close()
        _sync_timer = nil
    end
    _sync_timer = (vim.uv or vim.loop).new_timer()
    _sync_timer:start(300, 0, vim.schedule_wrap(function()
        _sync_timer = nil
        require("wyt.idea").sync_group_ideas_to_ideas()
    end))
end

function M.setup()
    -- F4: named augroup with clear=true prevents duplicate autocmds on re-setup
    local group = api.nvim_create_augroup("WYT_Plugin", { clear = true })

    api.nvim_create_autocmd("BufEnter", {
        group = group,
        pattern = "plan.wyt.md",
        callback = function(ev)
            local project = require("wyt.project")
            if not project.setup() then return end
            -- F9: apply project language to the localization module
            loc.set_lang(project.lang)
            -- F8: buffer-local keymaps — only active in this plan.wyt.md buffer
            require("wyt.mappings").setup_buf(ev.buf)
        end,
        desc = loc.t("set_lang_on_enter")
    })

    -- P15: buffer-local keymaps for text.wyt.md placeholder expansion
    api.nvim_create_autocmd("BufEnter", {
        group = group,
        pattern = "text.wyt.md",
        callback = function(ev)
            local project = require("wyt.project")
            if not project.setup() then return end
            loc.set_lang(project.lang)
            require("wyt.mappings").setup_text_buf(ev.buf)
        end,
        desc = "WYT: set up text buffer keymaps",
    })

    api.nvim_create_autocmd({"TextChanged", "TextChangedP", "InsertLeave"}, {
        group = group,
        pattern = "*plan.wyt.md",
        -- O3: debounced — was firing the full sync on every single keystroke
        callback = debounced_sync,
        desc = loc.t("sync_group_ideas_desc")
    })

    -- P11: auto-commit on write for wyt content files
    api.nvim_create_autocmd("BufWritePost", {
        group = group,
        pattern = {"*plan.wyt.md", "*text.wyt.md"},
        callback = function()
            local project = require("wyt.project")
            if not project.setup() then return end
            project.commit_changes("Save: " .. vim.fn.expand("%:t"))
        end,
        desc = "WYT: auto-commit on write",
    })
end

return M
