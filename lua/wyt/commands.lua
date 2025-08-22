local config = require("wyt.config")
local llm = require("wyt.llm")
local loc = require("wyt.localization")
local project = require("wyt.project")
local idea = require("wyt.idea")
local group = require("wyt.group")

local M = {}

-- Comando para configurar el proveedor y la API Key
function M.setup_command()
    vim.api.nvim_create_user_command("WYTConfig", function(args)
        if #args.fargs ~= 2 then
            print(loc.t("config_usage") or "[WYT] Usage: :WYTConfig <provider> <api_key>")
            return
        end
        local provider = args.fargs[1]
        local key = args.fargs[2]
        config.setup({ llm_provider = provider, api_key = key })
        print(loc.t("config_updated") .. provider)
    end, {
        nargs = "+", -- acepta uno o más argumentos
        complete = function(arglead)
            return {"openai", "claude"}
        end,
        desc = loc.t("set_provider")
    })

    vim.api.nvim_create_user_command("WYTSetLang", function(args)
        local lang = args.fargs[1]
        loc.set_lang(lang)
        print("[WYT] Language set to: " .. lang)
    end, {
        nargs = 1,
        complete = function(arglead)
            return {"en", "es"}
        end,
        desc = "Set plugin language (en/es)"
    })

    vim.api.nvim_create_user_command("WYTNew", function(args)
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
            print(loc.t("new_usage"))
        end
    end, {
        nargs = 1,
        range = true,
        complete = function(arglead)
            return {"p", "i", "g"}
        end,
        desc = loc.t("new_desc")
    })
end

-- Comando para generar texto literario usando la metodología propia
function M.generate_text_command()
    vim.api.nvim_create_user_command("WYTGenerate", function(args)
        local prompt = args.args
        local result = llm.generate_text(prompt)
        print(loc.t("result") .. result)
    end, {
        nargs = "?",
        desc = loc.t("generate_text")
    })
end

function M.nav_command()
    vim.api.nvim_create_user_command("WYTNav", function()
        if not project.setup() then return end
        local sep = package.config:sub(1,1)
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
            vim.cmd("e " .. root .. clean_choice)
        end)
    end, {
        desc = loc.t("nav_desc"),
    })
end

function M.goto_command()
    vim.api.nvim_create_user_command("WYTGoto", function(args)
        if not project.setup() then return end
        local arg = args.fargs[1]
        local root = project.project_root
        local sep = package.config:sub(1,1)
        local current_path = vim.api.nvim_buf_get_name(0)
        local target_path = nil

        if arg == "plan" then
            target_path = project.plan_path
        elseif arg == "config" then
            target_path = project.config_path
        elseif arg == "text" then
            target_path = root .. "text.wyt.md"
        elseif arg == "export" then
            target_path = root .. "export.wyt.md"
        elseif arg == "parent" then
            local parent = root:match("^(.*"..sep..")[^"..sep.."]+"..sep.."$")
            if parent and parent ~= "" and parent ~= root then
                local parent_plan = parent .. "plan.wyt.md"
                if vim.fn.filereadable(parent_plan) == 1 then
                    target_path = parent_plan
                else
                    print(loc.t("goto_no_parent_plan"))
                    return
                end
            else
                print(loc.t("goto_no_parent"))
                return
            end
        else
            print(loc.t("goto_invalid_arg"))
            return
        end

        if target_path then
            vim.cmd("e " .. target_path)
        end
    end, {
        nargs = 1,
        complete = function(arglead)
            return {"plan", "config", "text", "export", "parent"}
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
