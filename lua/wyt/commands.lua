-- O1: only lightweight localization required at top (needed for `desc` fields at command creation time)
-- all other modules are required lazily inside callbacks
local loc = require("wyt.localization")

local M = {}

function M.setup_command()
    vim.api.nvim_create_user_command("WYTConfig", function(args)
        -- O1: lazy require
        local config = require("wyt.config")
        if #args.fargs ~= 2 then
            -- O6: vim.notify instead of print
            vim.notify(loc.t("config_usage") or "[WYT] Usage: :WYTConfig <provider> <api_key>", vim.log.levels.WARN)
            return
        end
        local provider = args.fargs[1]
        local key = args.fargs[2]
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
        local result = llm.generate_text(prompt)
        -- P8: insert result at cursor position instead of just notifying
        local row = vim.api.nvim_win_get_cursor(0)[1]
        local result_lines = vim.split(result, "\n", { plain = true })
        vim.api.nvim_buf_set_lines(0, row, row, false, result_lines)
        vim.notify("[WYT] Text generated and inserted at cursor", vim.log.levels.INFO)
    end, {
        nargs = "?",
        desc = loc.t("generate_text")
    })
end

function M.nav_command()
    vim.api.nvim_create_user_command("WYTNav", function()
        -- O1: lazy require
        local project = require("wyt.project")
        if not project.setup() then return end
        local root = project.project_root
        local files = vim.fn.glob(root .. "**/*", true, true)
        local current_file = vim.api.nvim_buf_get_name(0)
        local display = {}
        for _, f in ipairs(files) do
            local rel = f:sub(#root + 1)
            if f == current_file then
                table.insert(display, "→ " .. rel)
            else
                table.insert(display, rel)
            end
        end
        vim.ui.select(display, {prompt = loc.t("nav_select")}, function(choice)
            if not choice or choice:sub(1,2) == "→ " then return end
            -- F5: fnameescape prevents path injection
            vim.cmd("edit " .. vim.fn.fnameescape(root .. choice))
        end)
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
        local sep = package.config:sub(1,1)
        local target_path = nil

        if arg == "plan" then
            target_path = project.section_plan_path
        elseif arg == "config" then
            target_path = project.section_config_path
        elseif arg == "text" then
            target_path = root .. "text.wyt.md"
        elseif arg == "export" then
            target_path = root .. "export.wyt.md"
        elseif arg == "parent" then
            local parent = root:match("^(.*"..sep..")[^"..sep.."]+"..sep.."$")
            if parent and parent ~= "" and parent ~= root then
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
            -- F5: fnameescape prevents path injection
            vim.cmd("edit " .. vim.fn.fnameescape(target_path))
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

function M.setup()
    M.setup_command()
    M.generate_text_command()
    M.nav_command()
    M.goto_command()
end

return M
