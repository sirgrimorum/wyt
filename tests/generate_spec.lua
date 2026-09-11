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

    it("falls back to free outside a WYT file, where only the frame applies", function()
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

describe("generate.context keeps the prompt short", function()
    it("clips a very long block rather than sending the whole file", function()
        local root = helpers.project({ type = "novel", lang = "en" })
        local long = string.rep("word ", 400)
        local ctx = context_at(root, "text.wyt.md", { long, "" }, 2)
        assert.truthy(#ctx.before <= 600, "before was " .. #ctx.before .. " bytes")
        helpers.cleanup(root)
    end)

    it("collapses the newlines inside a block into single spaces", function()
        local root = helpers.project({ type = "novel", lang = "en" })
        local ctx = context_at(root, "text.wyt.md", { "One line.", "Another line.", "" }, 3)
        assert.equals("One line. Another line.", ctx.before)
        helpers.cleanup(root)
    end)
end)
