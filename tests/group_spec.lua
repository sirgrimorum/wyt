-- group.lua's idea tagging. An idea keeps living under `## Ideas` after it is
-- grouped; the tag is what says which group claimed it, and an idea may belong
-- to more than one.
local helpers = require("tests.helpers")
local group = require("wyt.group")

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
