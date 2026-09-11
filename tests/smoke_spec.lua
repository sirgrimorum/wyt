-- The cheap checks that catch a whole class of breakage: a module that no
-- longer loads, a require cycle, a command that was renamed in one place and
-- not the other. None of this needs a project or a provider.
local helpers = require("tests.helpers")

local MODULES = {
    "autocmd", "commands", "config", "export", "generate", "group", "health",
    "idea", "init", "llm", "localization", "mappings", "nav", "plan", "project",
    "search", "secret", "section_kinds", "text", "types", "ui",
}

describe("every module loads", function()
    for _, name in ipairs(MODULES) do
        it(name, function()
            local ok, err = pcall(require, "wyt." .. name)
            assert.truthy(ok, tostring(err))
        end)
    end
end)

describe("every module returns a table", function()
    it("so require() gives callers something to call", function()
        for _, name in ipairs(MODULES) do
            assert.equals("table", type(require("wyt." .. name)), name .. " returned a non-table")
        end
    end)
end)

describe("setup registers the commands the docs promise", function()
    local expected = {
        "WYTConfig", "WYTSetLang", "WYTNew", "WYTGenerate",
        "WYTNav", "WYTGoto", "WYTExport", "WYTExpand", "WYTSearch",
    }

    it("creates each one", function()
        require("wyt.commands").setup()
        local commands = vim.api.nvim_get_commands({})
        for _, name in ipairs(expected) do
            assert.is_not_nil(commands[name], name .. " was not created")
        end
    end)

    it("gives each one a description, which is what :command lists", function()
        require("wyt.commands").setup()
        local commands = vim.api.nvim_get_commands({})
        for _, name in ipairs(expected) do
            local desc = commands[name] and commands[name].definition
            assert.truthy(desc and desc ~= "", name .. " has no description")
        end
    end)
end)

describe("WYTGoto knows where each file lives", function()
    local root

    before_each(function()
        helpers.cleanup(root)
        root = helpers.project({ type = "novel", name = "A City" })
        require("wyt.commands").setup()
    end)

    -- The command ends by opening a file; record which one instead.
    local function goto_target(arg)
        local ui = require("wyt.ui")
        local original = ui.edit_file
        local opened
        ui.edit_file = function(path) opened = path end
        local messages, restore_notify = helpers.capture_notify()
        vim.cmd("WYTGoto " .. arg)
        restore_notify()
        ui.edit_file = original
        return opened, messages
    end

    it("opens the plan of the section the cursor is in", function()
        assert.matches("plan%.wyt%.md$", (goto_target("plan")))
    end)

    it("opens the config of that same section", function()
        assert.matches("config%.wyt%.yml$", (goto_target("config")))
    end)

    it("resolves export against the project root, not the section", function()
        -- The resolved root comes back with the platform's own separator, so
        -- both sides are normalised before they are compared.
        local function norm(p) return (p:gsub("\\", "/")) end
        assert.equals(norm(root .. "export.wyt.md"), norm((goto_target("export"))))
    end)

    it("says so at the root, which has no parent to go up to", function()
        local opened, messages = goto_target("parent")
        assert.is_nil(opened)
        assert.truthy(#messages > 0)
    end)

    it("rejects an argument it does not know", function()
        local opened, messages = goto_target("nonsense")
        assert.is_nil(opened)
        assert.truthy(#messages > 0)
    end)
end)

describe("health.check runs without a project open", function()
    it("reports rather than erroring", function()
        local ok = pcall(function()
            -- :checkhealth's reporters are only defined inside a health buffer.
            local health = vim.health or {}
            local stubs = {}
            for _, fn in ipairs({ "start", "ok", "warn", "error", "info" }) do
                if not health[fn] then
                    stubs[#stubs + 1] = fn
                    health[fn] = function() end
                end
            end
            vim.health = health
            require("wyt.health").check()
            for _, fn in ipairs(stubs) do health[fn] = nil end
        end)
        assert.truthy(ok)
    end)
end)
