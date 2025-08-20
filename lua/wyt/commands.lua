local config = require("wyt.config")
local llm = require("wyt.llm")
local loc = require("wyt.localization")
local project = require("wyt.project")

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
        if args.fargs[1] == "p" then
            project.new_project()
        else
            print(loc.t("new_usage"))
        end
    end, {
        nargs = 1,
        complete = function(arglead)
            return {"p"}
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

function M.setup()
    M.setup_command()
    M.generate_text_command()
end

return M
