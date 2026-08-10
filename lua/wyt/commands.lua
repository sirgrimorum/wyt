-- O1: only lightweight localization required at top (needed for `desc` fields at command creation time)
-- all other modules are required lazily inside callbacks
local loc = require("wyt.localization")

local M = {}

function M.setup_command()
    vim.api.nvim_create_user_command("WYTConfig", function(args)
        -- O1: lazy require
        local config = require("wyt.config")
        if #args.fargs < 1 or #args.fargs > 2 then
            -- O6: vim.notify instead of print
            vim.notify(loc.t("config_usage") or "[WYT] Usage: :WYTConfig <provider> [api_key]", vim.log.levels.WARN)
            return
        end
        local provider = args.fargs[1]
        local key = args.fargs[2]
        if key then
            -- Typing the key on the command line writes it to :history, which
            -- Neovim persists to the shada file. Scrub both entries.
            vim.notify(
                "[WYT] Key passed on the command line — prefer :WYTConfig " .. provider .. " and enter it at the prompt.",
                vim.log.levels.WARN
            )
            vim.fn.histdel("cmd", -1)
            vim.fn.histdel(":", "WYTConfig")
        else
            key = vim.fn.inputsecret("API key for " .. provider .. ": ")
            if key == "" then
                vim.notify("[WYT] Cancelled — provider unchanged.", vim.log.levels.WARN)
                return
            end
        end
        config.setup({ llm_provider = provider, api_key = key })
        vim.notify(loc.t("config_updated") .. provider, vim.log.levels.INFO)
    end, {
        nargs = "+",
        complete = function(arglead)
            return vim.tbl_filter(function(v)
                return v:find(arglead, 1, true) == 1
            end, {"openai", "claude"})
        end,
        desc = loc.t("set_provider")
    })

    vim.api.nvim_create_user_command("WYTSetLang", function(args)
        local lang_loc = require("wyt.localization")
        local project = require("wyt.project")
        local lang = args.fargs[1]
        lang_loc.set_lang(lang)
        -- P9: persist language to config.wyt.yml so it survives session restarts
        if project.setup() then
            local config_content = project.read_file(project.config_path) or ""
            if config_content:match("lang:%s*%w+") then
                config_content = config_content:gsub("lang:%s*%w+", "lang: " .. lang)
            else
                config_content = config_content .. "lang: " .. lang .. "\n"
            end
            project.write_file(project.config_path, config_content)
            project.commit_changes("Set language to: " .. lang)
            vim.notify("[WYT] Language set to " .. lang .. " and saved to project config", vim.log.levels.INFO)
        else
            vim.notify("[WYT] Language set to: " .. lang .. " (session only — no project found)", vim.log.levels.INFO)
        end
    end, {
        nargs = 1,
        complete = function(arglead)
            return vim.tbl_filter(function(v)
                return v:find(arglead, 1, true) == 1
            end, {"en", "es"})
        end,
        desc = "Set plugin language (en/es)"
    })

    vim.api.nvim_create_user_command("WYTNew", function(args)
        -- O1: lazy requires
        local project = require("wyt.project")
        local idea = require("wyt.idea")
        local group = require("wyt.group")
        if args.fargs[1] == "g" then
            if project.setup() then
                group.new_group(args.line1, args.line2)
            end
        elseif args.fargs[1] == "p" then
            project.new_project()
        elseif args.fargs[1] == "i" then
            if project.setup() then
                idea.new_idea()
            end
        else
            vim.notify(loc.t("new_usage"), vim.log.levels.WARN)
        end
    end, {
        nargs = 1,
        range = true,
        complete = function(arglead)
            return vim.tbl_filter(function(v)
                return v:find(arglead, 1, true) == 1
            end, {"p", "i", "g"})
        end,
        desc = loc.t("new_desc")
    })
end

function M.generate_text_command()
    vim.api.nvim_create_user_command("WYTGenerate", function(args)
        local llm = require("wyt.llm")
        local prompt = args.args
        -- P8: async — insert result at cursor once the callback fires
        local buf = vim.api.nvim_get_current_buf()
        local row = vim.api.nvim_win_get_cursor(0)[1]
        vim.notify(loc.t("llm_generating"), vim.log.levels.INFO)
        llm.generate_text(prompt, function(result, err)
            if err or not result then
                vim.notify(loc.t("llm_error") .. (err or ""), vim.log.levels.WARN)
                return
            end
            -- Free-form or not, it is going into a file whose headings are
            -- structure; the model does not get to add any.
            local result_lines = vim.split(llm.to_prose(result), "\n", { plain = true })
            vim.api.nvim_buf_set_lines(buf, row, row, false, result_lines)
            vim.notify("[WYT] Text generated and inserted at cursor", vim.log.levels.INFO)
        end)
    end, {
        nargs = "?",
        desc = loc.t("generate_text")
    })
end

function M.nav_command()
    vim.api.nvim_create_user_command("WYTNav", function()
        -- P10: hierarchical tree navigation via nav.lua
        local project = require("wyt.project")
        if not project.setup() then return end
        require("wyt.nav").navigate()
    end, {
        desc = loc.t("nav_desc"),
    })
end

function M.goto_command()
    vim.api.nvim_create_user_command("WYTGoto", function(args)
        -- O1: lazy require
        local project = require("wyt.project")
        if not project.setup() then return end
        local arg = args.fargs[1]
        local root = project.project_root
        -- F14: plan/config/text/parent are all relative to the *current section*;
        -- only export is a root-level file. `text` and `parent` were resolving
        -- against the root, so from a section they hit the wrong file.
        local section = project.current_section_dir
        local target_path = nil

        if arg == "plan" then
            target_path = project.section_plan_path
        elseif arg == "config" then
            target_path = project.section_config_path
        elseif arg == "text" then
            target_path = section .. "text.wyt.md"
        elseif arg == "export" then
            target_path = root .. "export.wyt.md"
        elseif arg == "parent" then
            -- F13: match either separator; package.config's "\" never matched a
            -- forward-slash root on Windows, so parent lookup always failed
            local parent = section:match("^(.*[\\/])[^\\/]+[\\/]$")
            if section == root then parent = nil end  -- already at the project root
            if parent and parent ~= "" and parent ~= section then
                local parent_plan = parent .. "plan.wyt.md"
                -- O4: fs_stat instead of vim.fn.filereadable
                if (vim.uv or vim.loop).fs_stat(parent_plan) then
                    target_path = parent_plan
                else
                    vim.notify(loc.t("goto_no_parent_plan"), vim.log.levels.WARN)
                    return
                end
            else
                vim.notify(loc.t("goto_no_parent"), vim.log.levels.WARN)
                return
            end
        else
            vim.notify(loc.t("goto_invalid_arg"), vim.log.levels.WARN)
            return
        end

        if target_path then
            require("wyt.ui").edit_file(target_path)
        end
    end, {
        nargs = 1,
        complete = function(arglead)
            return vim.tbl_filter(function(v)
                return v:find(arglead, 1, true) == 1
            end, {"plan", "config", "text", "export", "parent"})
        end,
        desc = loc.t("goto_desc")
    })
end

function M.export_command()
    vim.api.nvim_create_user_command("WYTExport", function()
        require("wyt.export").export()
    end, { desc = loc.t("export_desc") })
end

function M.expand_command()
    -- P15: expand placeholders in text.wyt.md
    vim.api.nvim_create_user_command("WYTExpand", function(args)
        local text = require("wyt.text")
        local sub = args.fargs[1]
        if sub == "next" then
            text.expand_next()
        elseif sub == "prev" then
            text.expand_prev()
        else
            text.expand_at_cursor()
        end
    end, {
        nargs = "?",
        complete = function(arglead)
            return vim.tbl_filter(function(v)
                return v:find(arglead, 1, true) == 1
            end, { "next", "prev" })
        end,
        desc = loc.t("expand_desc"),
    })
end

function M.search_command()
    -- P7: search in definition sections
    vim.api.nvim_create_user_command("WYTSearch", function()
        require("wyt.search").search()
    end, { desc = loc.t("search_desc") })
end

function M.setup()
    M.setup_command()
    M.generate_text_command()
    M.nav_command()
    M.goto_command()
    M.export_command()
    M.expand_command()
    M.search_command()
end

return M
