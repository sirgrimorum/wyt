-- Shared fixtures. Two things every spec that touches more than pure strings
-- needs: a real project on disk, and a way to see what a prompt came out as
-- without calling a provider.
local H = {}

--- Build a project in a fresh temp directory and open its plan, so that
--- `project.setup()` resolves the root from the buffer the way it does in use.
--- `opts`: { type, lang, sections, name, description, plan }
--- Returns the root path, with a trailing separator.
function H.project(opts)
    opts = opts or {}
    local project = require("wyt.project")
    -- A project created inside another project resolves its root to the outer
    -- config, so every fixture gets its own temp tree.
    local root = vim.fn.tempname() .. "/p/"
    vim.fn.mkdir(root, "p")

    local lang = opts.lang or "en"
    local type_name = opts.type or "essay"
    local sections = opts.sections
    if sections == nil then sections = true end

    H.write(root .. "config.wyt.yml", string.format(
        "lang: %s\ntype: %s\ncontent_type: %s\nsections: %s\nname: %s\n",
        lang, type_name, opts.content_type or "content", tostring(sections),
        opts.name or "Fixture"))

    local plan = opts.plan
    if not plan then
        local desc_header = "## " .. require("wyt.localization").t("description_section", lang)
        plan = table.concat({
            "# " .. (opts.name or "Fixture"),
            "",
            desc_header,
            "",
            opts.description or "",
            "",
            "## " .. require("wyt.localization").t("ideas_section", lang),
            "",
        }, "\n")
    end
    H.write(root .. "plan.wyt.md", plan)

    vim.cmd("edit " .. vim.fn.fnameescape(root .. "plan.wyt.md"))
    assert(project.setup(), "project.setup() failed for the fixture at " .. root)
    return root
end

function H.write(path, body)
    local dir = path:match("^(.*)[\\/][^\\/]+$")
    if dir then vim.fn.mkdir(dir, "p") end
    local f = assert(io.open(path, "w"))
    f:write(body)
    f:close()
end

function H.read(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local body = f:read("*a")
    f:close()
    return body
end

--- Remove a fixture tree. Safe to call on a path H.project returned.
function H.cleanup(root)
    if root and root ~= "" then vim.fn.delete(vim.fn.fnamemodify(root, ":h:h"), "rf") end
end

--- Replace `llm.generate_text` with a capture. Returns a table whose `prompt`
--- field holds the last prompt built, and a restore function.
--- `reply` is what the fake provider answers with.
function H.capture_prompt(reply)
    local llm = require("wyt.llm")
    local original = llm.generate_text
    local captured = {}
    llm.generate_text = function(prompt, callback)
        captured.prompt = prompt
        callback(reply or "", nil)
    end
    return captured, function() llm.generate_text = original end
end

--- Drive `vim.ui.select` and `vim.ui.input` from scripted answers, the way the
--- interactive flows expect them. `answers` is a list consumed in order; a
--- select answer may be the item itself or its 1-based index. Returns a log of
--- every prompt shown, and a restore function.
function H.scripted_ui(answers)
    local i = 0
    local log = {}
    local original = { select = vim.ui.select, input = vim.ui.input }

    vim.ui.select = function(items, opts, on_choice)
        i = i + 1
        local answer = answers[i]
        log[#log + 1] = { kind = "select", prompt = opts and opts.prompt, items = items, answer = answer }
        if answer == nil then return on_choice(nil) end
        if type(answer) == "number" then return on_choice(items[answer], answer) end
        for idx, item in ipairs(items) do
            if item == answer then return on_choice(item, idx) end
        end
        on_choice(answer, nil)
    end

    vim.ui.input = function(opts, on_confirm)
        i = i + 1
        local answer = answers[i]
        log[#log + 1] = { kind = "input", prompt = opts and opts.prompt, answer = answer }
        on_confirm(answer)
    end

    return log, function()
        vim.ui.select = original.select
        vim.ui.input = original.input
    end
end

--- Silence vim.notify for one block, and collect what it was told.
function H.capture_notify()
    local original = vim.notify
    local messages = {}
    vim.notify = function(msg, level) messages[#messages + 1] = { msg = msg, level = level } end
    return messages, function() vim.notify = original end
end

return H
