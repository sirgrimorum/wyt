-- plan.lua's plan-editing helpers. Run with: nvim --headless -l tests/runner.lua

local plan = require("wyt.plan")
local project = require("wyt.project")

-- Stub project.t() so tests don't need a real project on disk
project.lang = "en"

describe("plan.add_item_to_section", function()
    it("appends item to existing section", function()
        local content = "# Title\n\n## Ideas\n- First idea\n\n## Group: A\n"
        local result = plan.add_item_to_section(content, "Ideas", "New idea")
        assert.truthy(result:find("- New idea", 1, true))
        -- new idea should appear before the next section
        local ideas_pos = result:find("## Ideas")
        local new_pos = result:find("- New idea")
        local group_pos = result:find("## Group: A")
        assert.truthy(ideas_pos < new_pos)
        assert.truthy(new_pos < group_pos)
    end)

    it("creates section if it does not exist", function()
        local content = "# Title\n"
        local result = plan.add_item_to_section(content, "Ideas", "First idea")
        assert.truthy(result:find("## Ideas", 1, true))
        assert.truthy(result:find("- First idea", 1, true))
    end)

    -- The header was looked for as a pattern, so "(1)" was read as a capture and
    -- "-2" as a quantifier: the section was not found and a second one with the
    -- same name was appended to the file.
    it("finds a section whose name carries pattern magic", function()
        local content = "# Title\n\n## Group: Cap (1)\n- First idea\n"
        local result = plan.add_item_to_section(content, "Group: Cap (1)", "New idea")
        local _, headers = result:gsub("## Group: Cap %(1%)", "")
        assert.equals(1, headers)
        assert.truthy(result:find("- New idea", 1, true))
    end)

    it("finds a section whose name holds a hyphen", function()
        local content = "# Title\n\n## Group: Nota-2\n- First idea\n"
        local result = plan.add_item_to_section(content, "Group: Nota-2", "New idea")
        local _, headers = result:gsub("## Group: Nota%-2", "")
        assert.equals(1, headers)
    end)

    it("strips newlines from item", function()
        local content = "# Title\n\n## Ideas\n"
        local result = plan.add_item_to_section(content, "Ideas", "idea\nwith newline")
        assert.falsy(result:find("idea\nwith newline", 1, true))
        assert.truthy(result:find("idea", 1, true))
    end)
end)

describe("plan.is_group_tagged", function()
    it("detects implemented tag", function()
        project.lang = "en"
        local content = "## Group: My Group [Implemented]\n- idea\n"
        assert.truthy(plan.is_group_tagged(content, "My Group", "implemented"))
    end)

    it("returns false when tag absent", function()
        local content = "## Group: My Group\n- idea\n"
        assert.falsy(plan.is_group_tagged(content, "My Group", "implemented"))
    end)

    it("returns false for nil content", function()
        assert.falsy(plan.is_group_tagged(nil, "My Group", "implemented"))
    end)
end)

describe("project.slugify", function()
    it("lowercases and replaces spaces with hyphens", function()
        assert.equals("my-group", project.slugify("My Group"))
    end)

    it("removes special characters", function()
        assert.equals("hello-world", project.slugify("Hello, World!"))
    end)

    it("handles already-slugified input", function()
        assert.equals("already-slugified", project.slugify("already-slugified"))
    end)
end)
