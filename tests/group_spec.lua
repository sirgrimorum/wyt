-- group.lua's idea tagging. An idea keeps living under `## Ideas` after it is
-- grouped; the tag is what says which group claimed it, and an idea may belong
-- to more than one.
local helpers = require("tests.helpers")
local group = require("wyt.group")

describe("group.move_group", function()
    local root

    before_each(function()
        helpers.cleanup(root)
        root = helpers.project({ type = "essay", lang = "en" })
    end)

    -- The last group has no blank line after it, which is the case that used to
    -- carry the separator to the wrong side of the swap.
    local plan = { "## Ideas", "- a", "", "## Group: One", "- x", "", "## Group: Two", "- y" }
    local swapped = { "## Ideas", "- a", "", "## Group: Two", "- y", "", "## Group: One", "- x" }

    local function move(from_row, direction)
        vim.api.nvim_buf_set_lines(0, 0, -1, false, plan)
        vim.api.nvim_win_set_cursor(0, { from_row, 0 })
        group.move_group(direction)
        return vim.api.nvim_buf_get_lines(0, 0, -1, false), vim.api.nvim_win_get_cursor(0)[1]
    end

    it("moves the last group up and keeps the gap between the two", function()
        local lines, row = move(7, "up")
        assert.same(swapped, lines)
        assert.equals(4, row)
    end)

    it("moves a group down past the last one and follows it with the cursor", function()
        local lines, row = move(4, "down")
        assert.same(swapped, lines)
        assert.equals(7, row)
    end)
end)

describe("group.new_group asks the model with the type's name", function()
    it("never sends the type id, in a Spanish project", function()
        local root = helpers.project({ type = "long_novel", lang = "es", plan = "# F\n\n## Ideas\n- una idea\n" })
        vim.api.nvim_win_set_cursor(0, { 4, 0 })
        -- What the BufEnter autocmd does in use; the suite registers no autocmds.
        require("wyt.localization").set_lang("es")
        local multi_select = group.multi_select
        group.multi_select = function(_, opts, cb) cb(opts.preselected) end
        local captured, restore = helpers.capture_prompt("El andén vacío")
        local _, restore_ui = helpers.scripted_ui({ "Sí", "" })
        helpers.capture_notify()
        local ok, err = pcall(group.new_group)
        group.multi_select = multi_select
        restore()
        restore_ui()
        assert(ok, err)
        assert.matches("Novela larga", captured.prompt)
        assert.has_no_match("long_novel", captured.prompt)
        helpers.cleanup(root)
    end)
end)

describe("group.mark_ideas_as_grouped", function()
    local root

    before_each(function()
        helpers.cleanup(root)
        root = helpers.project({ type = "essay", lang = "en" })
    end)

    it("tags the ideas it was given", function()
        local plan = "# T\n\n## Ideas\n- first idea\n- second idea\n"
        local out = group.mark_ideas_as_grouped(plan, { "first idea" }, "One")
        assert.matches("%- first idea %[Group: One%]", out)
    end)

    it("leaves the ideas it was not given alone", function()
        local plan = "# T\n\n## Ideas\n- first idea\n- second idea\n"
        local out = group.mark_ideas_as_grouped(plan, { "first idea" }, "One")
        assert.matches("%- second idea\n", out)
    end)

    it("keeps an earlier tag when a second group claims the same idea", function()
        local plan = "# T\n\n## Ideas\n- first idea\n"
        local once = group.mark_ideas_as_grouped(plan, { "first idea" }, "One")
        local twice = group.mark_ideas_as_grouped(once, { "first idea" }, "Two")
        assert.matches("%[Group: One%]", twice)
        assert.matches("%[Group: Two%]", twice)
    end)

    it("does not tag the same group twice", function()
        local plan = "# T\n\n## Ideas\n- first idea\n"
        local once = group.mark_ideas_as_grouped(plan, { "first idea" }, "One")
        local twice = group.mark_ideas_as_grouped(once, { "first idea" }, "One")
        local _, count = twice:gsub("%[Group: One%]", "")
        assert.equals(1, count)
    end)

    it("touches nothing outside the Ideas section", function()
        local plan = "# T\n\n## Ideas\n- first idea\n\n## Group: A\n- first idea\n"
        local out = group.mark_ideas_as_grouped(plan, { "first idea" }, "One")
        local body = out:match("## Group: A\n(.*)$")
        assert.has_no_match("%[Group: One%]", body)
    end)

    it("returns the plan untouched when there is no Ideas section", function()
        local plan = "# T\n\n## Group: A\n"
        assert.equals(plan, group.mark_ideas_as_grouped(plan, { "anything" }, "One"))
    end)

    it("uses the project's own word for the tag", function()
        helpers.cleanup(root)
        root = helpers.project({ type = "essay", lang = "es" })
        local plan = "# T\n\n## Ideas\n- una idea\n"
        assert.matches("%[Grupo: Uno%]", group.mark_ideas_as_grouped(plan, { "una idea" }, "Uno"))
    end)
end)
