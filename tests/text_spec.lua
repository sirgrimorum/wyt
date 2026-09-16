-- text.lua: finding a placeholder and replacing it with a paragraph. The
-- interactive choice is scripted, and the LLM call is answered by a stub, so
-- the whole expansion runs without a provider.
local helpers = require("tests.helpers")
local text = require("wyt.text")
local loc = require("wyt.localization")

local function placeholder(idea, lang)
    return "*" .. loc.t("create_paragraph", lang or "en") .. "[" .. idea .. "]*"
end

-- Open a text.wyt.md holding `lines`, with the cursor on `row`.
local function open_text(root, lines, row)
    local path = root .. "text.wyt.md"
    helpers.write(path, table.concat(lines, "\n"))
    vim.cmd("edit! " .. vim.fn.fnameescape(path))
    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_win_set_cursor(0, { row, 0 })
    return buf
end

local function lines_of(buf)
    return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

describe("expanding a placeholder with the LLM", function()
    local root, restores

    before_each(function()
        for _, r in ipairs(restores or {}) do r() end
        helpers.cleanup(root)
        restores = {}
        root = helpers.project({ type = "essay", lang = "en", sections = false })
    end)

    local function expand_with(reply, answers, fn)
        local captured, restore_llm = helpers.capture_prompt(reply)
        local _, restore_ui = helpers.scripted_ui(answers)
        local _, restore_notify = helpers.capture_notify()
        restores = { restore_llm, restore_ui, restore_notify }
        fn()
        return captured
    end

    it("replaces the placeholder line with the generated paragraph", function()
        local buf = open_text(root, { "## Group: One", "", placeholder("density"), "" }, 3)
        expand_with("Density is a choice.", { 2 }, text.expand_at_cursor)
        assert.equals("Density is a choice.", lines_of(buf)[3])
    end)

    it("gives the model the project frame and the plan it sits in", function()
        open_text(root, { placeholder("density") }, 1)
        local captured = expand_with("x.", { 2 }, text.expand_at_cursor)
        assert.matches("Project context: Essay", captured.prompt)
    end)

    it("asks for the paragraph this type wants", function()
        open_text(root, { placeholder("density") }, 1)
        local captured = expand_with("x.", { 2 }, text.expand_at_cursor)
        assert.matches("Write an argumentative paragraph", captured.prompt)
    end)

    it("strips a heading the model invented, which would become export structure", function()
        local buf = open_text(root, { placeholder("density") }, 1)
        expand_with("# Density\n\nDensity is a choice.", { 2 }, text.expand_at_cursor)
        assert.has_no_match("#", lines_of(buf)[1])
    end)

    it("leaves the placeholder alone when the choice is cancelled", function()
        local buf = open_text(root, { placeholder("density") }, 1)
        expand_with("x.", { nil }, text.expand_at_cursor)
        assert.equals(placeholder("density"), lines_of(buf)[1])
    end)

    it("leaves the placeholder alone when the model returns nothing", function()
        local buf = open_text(root, { placeholder("density") }, 1)
        expand_with("", { 2 }, text.expand_at_cursor)
        assert.equals(placeholder("density"), lines_of(buf)[1])
    end)

    it("says so instead of expanding when the cursor is not on a placeholder", function()
        local buf = open_text(root, { "Just prose." }, 1)
        local messages, restore_notify = helpers.capture_notify()
        text.expand_at_cursor()
        restore_notify()
        assert.equals("Just prose.", lines_of(buf)[1])
        assert.truthy(#messages > 0)
    end)
end)

describe("a summary placeholder", function()
    it("is told to merge the points it carries", function()
        local root = helpers.project({ type = "summary", lang = "en", sections = false })
        open_text(root, { placeholder("a; b; c") }, 1)
        local captured, restore_llm = helpers.capture_prompt("Merged.")
        local _, restore_ui = helpers.scripted_ui({ 2 })
        local _, restore_notify = helpers.capture_notify()
        text.expand_at_cursor()
        restore_llm(); restore_ui(); restore_notify()
        assert.matches("merge all of them into a single paragraph", captured.prompt)
        helpers.cleanup(root)
    end)
end)

describe("jumping between placeholders", function()
    local root, restores

    before_each(function()
        for _, r in ipairs(restores or {}) do r() end
        helpers.cleanup(root)
        restores = {}
        root = helpers.project({ type = "essay", lang = "en", sections = false })
    end)

    local function with_stubs(fn)
        local _, restore_llm = helpers.capture_prompt("Generated.")
        local _, restore_ui = helpers.scripted_ui({ 2, 2, 2 })
        local _, restore_notify = helpers.capture_notify()
        restores = { restore_llm, restore_ui, restore_notify }
        fn()
    end

    it("jumps forward to the next one and expands it in the same move", function()
        local buf = open_text(root, { placeholder("one"), "", placeholder("two") }, 1)
        with_stubs(text.expand_next)
        assert.equals(3, vim.api.nvim_win_get_cursor(0)[1])
        assert.equals("Generated.", lines_of(buf)[3])
        assert.equals(placeholder("one"), lines_of(buf)[1])
    end)

    it("jumps backward the same way", function()
        local buf = open_text(root, { placeholder("one"), "", placeholder("two") }, 3)
        with_stubs(text.expand_prev)
        assert.equals(1, vim.api.nvim_win_get_cursor(0)[1])
        assert.equals("Generated.", lines_of(buf)[1])
    end)

    it("says so when there is none below, rather than wrapping around", function()
        local buf = open_text(root, { placeholder("one"), "", "prose" }, 1)
        local messages, restore_notify = helpers.capture_notify()
        text.expand_next()
        restore_notify()
        assert.equals(1, vim.api.nvim_win_get_cursor(0)[1])
        assert.equals(placeholder("one"), lines_of(buf)[1])
        assert.truthy(#messages > 0)
    end)

    it("says so when there is none above", function()
        local messages, restore_notify = helpers.capture_notify()
        open_text(root, { "prose", "", placeholder("one") }, 3)
        text.expand_prev()
        restore_notify()
        assert.equals(3, vim.api.nvim_win_get_cursor(0)[1])
        assert.truthy(#messages > 0)
    end)
end)

describe("the placeholder marker is the project's own", function()
    it("is recognised in Spanish, where the marker text differs", function()
        local root = helpers.project({ type = "essay", lang = "es", sections = false })
        local buf = open_text(root, { placeholder("densidad", "es") }, 1)
        local _, restore_llm = helpers.capture_prompt("La densidad es una elección.")
        local _, restore_ui = helpers.scripted_ui({ 2 })
        local _, restore_notify = helpers.capture_notify()
        text.expand_at_cursor()
        restore_llm(); restore_ui(); restore_notify()
        assert.equals("La densidad es una elección.", lines_of(buf)[1])
        helpers.cleanup(root)
    end)

    it("is not matched without its square brackets", function()
        local root = helpers.project({ type = "essay", lang = "en", sections = false })
        local buf = open_text(root, { "*" .. loc.t("create_paragraph", "en") .. "density*" }, 1)
        local messages, restore_notify = helpers.capture_notify()
        text.expand_at_cursor()
        restore_notify()
        assert.matches("density%*$", lines_of(buf)[1])
        assert.truthy(#messages > 0)
        helpers.cleanup(root)
    end)
end)
