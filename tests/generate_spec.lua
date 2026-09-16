-- generate.lua reads the cursor as the question, so these check what it decides
-- from a buffer's shape: which mode, which heading, what is above and below.
local helpers = require("tests.helpers")
local generate = require("wyt.generate")

-- Put `lines` in a buffer named `name` and build the context at `row`.
-- The lines are set on the buffer rather than left to the file round-trip: a
-- trailing newline would drop the last entry, and `row` has to address a line
-- that exists, the way a real cursor always does.
local function context_at(root, name, lines, row)
    local path = root .. name
    helpers.write(path, table.concat(lines, "\n"))
    vim.cmd("edit! " .. vim.fn.fnameescape(path))
    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    assert(row <= #lines, "row " .. row .. " is past the " .. #lines .. " lines of the fixture")
    return generate.context(buf, row)
end

describe("generate.context decides the mode from the file", function()
    local root

    before_each(function()
        helpers.cleanup(root)
        root = helpers.project({ type = "novel", lang = "en" })
    end)

    it("asks for ideas inside a plan", function()
        assert.equals("plan", context_at(root, "plan.wyt.md", { "# T", "## Ideas", "" }, 3).mode)
    end)

    it("asks for prose inside a text file", function()
        assert.equals("text", context_at(root, "text.wyt.md", { "Something.", "" }, 2).mode)
    end)

    it("falls back to free outside a WYT file", function()
        assert.equals("free", context_at(root, "notes.md", { "Something.", "" }, 2).mode)
    end)
end)

describe("generate.context carries the project frame", function()
    it("names the type in the writer's language and adds the description", function()
        local root = helpers.project({ type = "long_novel", lang = "es", description = "Una ciudad que olvida." })
        local ctx = context_at(root, "text.wyt.md", { "Algo.", "" }, 2)
        assert.equals("es", ctx.lang)
        assert.matches("^Novela larga", ctx.project)
        assert.has_no_match("long_novel", ctx.project)
        helpers.cleanup(root)
    end)

    it("carries the paragraph kind the type wants", function()
        local root = helpers.project({ type = "essay", lang = "en" })
        assert.equals("an argumentative paragraph",
            context_at(root, "text.wyt.md", { "Something.", "" }, 2).prose_kind)
        helpers.cleanup(root)
    end)
end)

describe("generate.context reads what surrounds the cursor", function()
    local root

    before_each(function()
        helpers.cleanup(root)
        root = helpers.project({ type = "novel", lang = "en" })
    end)

    it("takes the block above and the block below", function()
        local ctx = context_at(root, "text.wyt.md",
            { "The platform was empty.", "", "", "The train did not come." }, 2)
        assert.equals("The platform was empty.", ctx.before)
        assert.equals("The train did not come.", ctx.after)
    end)

    it("leaves after nil at the end of the file, which asks for a continuation", function()
        local ctx = context_at(root, "text.wyt.md", { "The platform was empty.", "" }, 2)
        assert.equals("The platform was empty.", ctx.before)
        assert.is_nil(ctx.after)
    end)

    it("leaves before nil when there is only structure above", function()
        local ctx = context_at(root, "text.wyt.md", { "## Group: One", "", "Text." }, 2)
        assert.is_nil(ctx.before)
    end)

    it("does not read across a heading into another group", function()
        local ctx = context_at(root, "text.wyt.md",
            { "Other group's text.", "", "## Group: Two", "", "" }, 5)
        assert.is_nil(ctx.before)
    end)

    it("names the group the cursor is inside, without the marker", function()
        local ctx = context_at(root, "text.wyt.md", { "## Group: The platform", "", "Text.", "" }, 4)
        assert.equals("The platform", ctx.heading)
    end)

    it("strips the status tag from that name", function()
        local ctx = context_at(root, "text.wyt.md",
            { "## Group: The platform [Implemented]", "", "Text.", "" }, 4)
        assert.equals("The platform", ctx.heading)
    end)

    it("has no heading when the cursor is above every heading", function()
        assert.is_nil(context_at(root, "text.wyt.md", { "Text.", "" }, 2).heading)
    end)
end)

describe("generate.context in a plan", function()
    local root

    before_each(function()
        helpers.cleanup(root)
        root = helpers.project({ type = "novel", lang = "en" })
    end)

    it("lists the ideas already under the heading, so they are not repeated", function()
        local ctx = context_at(root, "plan.wyt.md",
            { "## Group: One", "- first idea", "- second idea", "" }, 4)
        assert.equals("first idea; second idea", ctx.existing)
    end)

    it("stops at the next heading", function()
        local ctx = context_at(root, "plan.wyt.md",
            { "## Group: One", "- first idea", "## Group: Two", "- other idea", "" }, 2)
        assert.equals("first idea", ctx.existing)
    end)

    it("leaves existing nil under a heading with no ideas yet", function()
        assert.is_nil(context_at(root, "plan.wyt.md", { "## Group: One", "" }, 2).existing)
    end)

    it("reads no surrounding prose, which a plan has none of", function()
        local ctx = context_at(root, "plan.wyt.md", { "## Group: One", "- an idea", "" }, 3)
        assert.is_nil(ctx.before)
        assert.is_nil(ctx.after)
    end)
end)

-- Run :WYTGenerate at `row` against a canned model reply; the buffer after.
local function run_at(root, name, lines, row, reply)
    context_at(root, name, lines, row)
    vim.api.nvim_win_set_cursor(0, { row, 0 })
    local _, restore = helpers.capture_prompt(reply)
    local notify_restore = select(2, helpers.capture_notify())
    local ok, err = pcall(generate.run, "")
    restore()
    notify_restore()
    assert(ok, err)
    return vim.api.nvim_buf_get_lines(0, 0, -1, false)
end

describe("generate.run inserts in the shape the file expects", function()
    local root

    before_each(function()
        helpers.cleanup(root)
        root = helpers.project({ type = "novel", lang = "es" })
    end)

    it("keeps a preamble and headings out of a plan, and a hashtag in", function()
        local out = run_at(root, "plan.wyt.md", { "## Ideas", "- una idea" }, 2,
            "Aquí tienes tres ideas:\n# Ideas\n1. Uno\n- Dos\n#silencio como motivo")
        assert.same({ "## Ideas", "- una idea", "- Uno", "- Dos", "- #silencio como motivo" }, out)
    end)

    it("separates a bridge from both paragraphs it sits between", function()
        local out = run_at(root, "text.wyt.md", { "Primero.", "Segundo." }, 1, "Puente.")
        assert.same({ "Primero.", "", "Puente.", "", "Segundo." }, out)
    end)

    it("adds no extra blank line where one is already there", function()
        local out = run_at(root, "text.wyt.md", { "Primero.", "", "Segundo." }, 2, "Puente.")
        assert.same({ "Primero.", "", "Puente.", "", "Segundo." }, out)
    end)
end)

describe("generate.run waits for a reply the writer does not", function()
    local root

    before_each(function()
        helpers.cleanup(root)
        root = helpers.project({ type = "novel", lang = "es" })
    end)

    -- Hold the reply, edit above the cursor, then answer: a line number taken
    -- before the request would now point at another paragraph.
    local function run_then_reply(lines, row, edit, reply)
        context_at(root, "text.wyt.md", lines, row)
        vim.api.nvim_win_set_cursor(0, { row, 0 })
        local llm = require("wyt.llm")
        local original = llm.generate_text
        local answer
        llm.generate_text = function(_, callback) answer = callback end
        local notify_restore = select(2, helpers.capture_notify())
        generate.run("")
        llm.generate_text = original
        edit()
        answer(reply, nil)
        notify_restore()
        return vim.api.nvim_buf_get_lines(0, 0, -1, false)
    end

    it("inserts where the cursor was, not where the line number was", function()
        local out = run_then_reply({ "Primero.", "", "Segundo." }, 2, function()
            vim.api.nvim_buf_set_lines(0, 0, 0, false, { "Nuevo primero.", "" })
        end, "Puente.")
        assert.same({ "Nuevo primero.", "", "Primero.", "", "Puente.", "", "Segundo." }, out)
    end)

    it("says so instead of erroring when the file is gone", function()
        local messages
        local out = run_then_reply({ "Primero.", "", "Segundo." }, 2, function()
            messages = helpers.capture_notify()
            local gone = vim.api.nvim_get_current_buf()
            vim.cmd("enew")
            vim.api.nvim_buf_delete(gone, { force = true })
        end, "Puente.")
        assert.same({ "" }, out)
        assert.matches("WYT", messages[#messages].msg)
    end)
end)

describe("generate.context keeps the prompt short", function()
    it("clips a very long block rather than sending the whole file", function()
        local root = helpers.project({ type = "novel", lang = "en" })
        local long = string.rep("word ", 400)
        local ctx = context_at(root, "text.wyt.md", { long, "" }, 2)
        assert.truthy(#ctx.before <= 600, "before was " .. #ctx.before .. " bytes")
        helpers.cleanup(root)
    end)

    -- Read backwards: the sentences the new prose has to follow are the ones
    -- right above the cursor, so a long paragraph loses its opening, not its end.
    it("keeps the end of the block above, and the start of the one below", function()
        local root = helpers.project({ type = "novel", lang = "en" })
        local long = "First sentence. " .. string.rep("filler ", 400) .. "Last sentence."
        local ctx = context_at(root, "text.wyt.md", { long, "", long }, 2)
        assert.matches("Last sentence%.$", ctx.before)
        assert.has_no_match("First sentence", ctx.before)
        assert.matches("^First sentence%.", ctx.after)
        assert.has_no_match("Last sentence", ctx.after)
        helpers.cleanup(root)
    end)

    it("cuts by character, so an accent never arrives half written", function()
        local root = helpers.project({ type = "novel", lang = "es" })
        -- The odd leading byte puts a 600th byte in the middle of an accent.
        local accented = "a" .. string.rep(string.char(0xC3, 0xA1), 700)
        local ctx = context_at(root, "text.wyt.md", { accented, "" }, 2)
        assert.equals(600, vim.fn.strchars(ctx.before))
        helpers.cleanup(root)
    end)

    it("collapses the newlines inside a block into single spaces", function()
        local root = helpers.project({ type = "novel", lang = "en" })
        local ctx = context_at(root, "text.wyt.md", { "One line.", "Another line.", "" }, 3)
        assert.equals("One line. Another line.", ctx.before)
        helpers.cleanup(root)
    end)
end)
