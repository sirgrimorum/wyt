-- project.lua: root resolution, the config reads every other module depends on,
-- and the plan parsing that decides what a group is.
local helpers = require("tests.helpers")
local project = require("wyt.project")

describe("project.slugify", function()
    it("lowercases and hyphenates", function()
        assert.equals("the-silence-of-cities", project.slugify("The Silence of Cities"))
    end)

    it("drops punctuation a folder name cannot carry", function()
        assert.equals("whats-left", project.slugify("What's left?"))
    end)

    it("collapses a run of spaces into one hyphen", function()
        assert.equals("a-b", project.slugify("a    b"))
    end)
end)

describe("project.read_file and write_file", function()
    local root

    before_each(function()
        helpers.cleanup(root)
        root = helpers.project({})
    end)

    it("round-trips content", function()
        project.write_file(root .. "scratch.md", "hello\nworld\n")
        assert.equals("hello\nworld\n", project.read_file(root .. "scratch.md"))
    end)

    it("returns nil for a file that is not there, rather than erroring", function()
        assert.is_nil(project.read_file(root .. "absent.md"))
    end)
end)

describe("project.get_project_type", function()
    it("reads the type out of the root config", function()
        local root = helpers.project({ type = "long_novel" })
        assert.equals("long_novel", project.get_project_type())
        helpers.cleanup(root)
    end)

    it("keeps the underscore: %w alone read short_story as short", function()
        local root = helpers.project({ type = "short_story" })
        assert.equals("short_story", project.get_project_type())
        helpers.cleanup(root)
    end)

    it("is not confused by content_type, whose key ends in the same word", function()
        local root = helpers.project({ type = "novel", content_type = "definition" })
        assert.equals("novel", project.get_project_type())
        helpers.cleanup(root)
    end)
end)

describe("project.description_context", function()
    it("names the type in the writer's language, never the id", function()
        local root = helpers.project({ type = "long_novel", lang = "es", description = "Una ciudad que olvida." })
        local plan = project.read_file(project.section_plan_path)
        local ctx = project.description_context(plan)
        assert.matches("^Novela larga", ctx)
        assert.has_no_match("long_novel", ctx)
        helpers.cleanup(root)
    end)

    it("adds the plan's Description when it has one", function()
        local root = helpers.project({ type = "essay", description = "On urban space." })
        assert.equals("Essay. On urban space.",
            project.description_context(project.read_file(project.section_plan_path)))
        helpers.cleanup(root)
    end)

    it("is just the type when the Description is empty", function()
        local root = helpers.project({ type = "essay", description = "" })
        assert.equals("Essay", project.description_context(project.read_file(project.section_plan_path)))
        helpers.cleanup(root)
    end)

    it("stops at the next section, so Ideas never leak into the frame", function()
        local root = helpers.project({ type = "essay", description = "On urban space." })
        local plan = project.read_file(project.section_plan_path) .. "- an idea that is not the description\n"
        assert.has_no_match("not the description", project.description_context(plan))
        helpers.cleanup(root)
    end)

    it("survives a plan with no Description section at all", function()
        local root = helpers.project({ type = "essay", plan = "# Fixture\n\n## Ideas\n\n" })
        assert.equals("Essay", project.description_context(project.read_file(project.section_plan_path)))
        helpers.cleanup(root)
    end)
end)

describe("project.section_level", function()
    local root

    before_each(function()
        helpers.cleanup(root)
        root = helpers.project({ type = "novel" })
    end)

    it("counts the project root as level 1", function()
        assert.equals(1, project.section_level(root))
    end)

    it("counts a section inside it as level 2, and so on down", function()
        assert.equals(2, project.section_level(root .. "one/"))
        assert.equals(3, project.section_level(root .. "one/two/"))
        assert.equals(4, project.section_level(root .. "one/two/three/"))
    end)

    it("measures the same whichever separator the path arrives with", function()
        assert.equals(3, project.section_level(root:gsub("/", "\\") .. "one\\two\\"))
    end)
end)

describe("project.is_definition_section", function()
    local root

    before_each(function()
        helpers.cleanup(root)
        root = helpers.project({})
    end)

    it("is true for a section that holds reference material", function()
        helpers.write(root .. "cast/config.wyt.yml", "type: novel\ncontent_type: definition\n")
        assert.truthy(project.is_definition_section(root .. "cast/"))
    end)

    it("is false for a section that holds text", function()
        helpers.write(root .. "one/config.wyt.yml", "type: novel\ncontent_type: content\n")
        assert.falsy(project.is_definition_section(root .. "one/"))
    end)

    it("is false when there is no config to read", function()
        assert.falsy(project.is_definition_section(root .. "absent/"))
    end)
end)

describe("project.section_kind_of", function()
    local root

    before_each(function()
        helpers.cleanup(root)
        root = helpers.project({})
    end)

    it("reads the archetype a section was created with", function()
        helpers.write(root .. "cast/config.wyt.yml", "type: novel\nsection_kind: characters\n")
        assert.equals("characters", project.section_kind_of(root .. "cast/"))
    end)

    it("reads prose as no archetype: the type alone guides the section", function()
        helpers.write(root .. "one/config.wyt.yml", "type: novel\nsection_kind: prose\n")
        assert.is_nil(project.section_kind_of(root .. "one/"))
    end)

    it("reads a config with no archetype as none", function()
        helpers.write(root .. "one/config.wyt.yml", "type: novel\n")
        assert.is_nil(project.section_kind_of(root .. "one/"))
    end)
end)

describe("project.get_groups and clean_group_name", function()
    local root

    before_each(function()
        helpers.cleanup(root)
        root = helpers.project({})
    end)

    it("finds every group in a plan", function()
        local plan = "# T\n\n## Ideas\n\n## Group: One\n\n## Group: Two\n"
        assert.same({ "One", "Two" }, project.get_groups(plan))
    end)

    it("strips the status tag, so a name is the same before and after", function()
        local plan = "# T\n\n## Group: One [Implemented]\n## Group: Two [Edited]\n"
        assert.same({ "One", "Two" }, project.get_groups(plan))
    end)

    it("strips the tag in the project's own language", function()
        local es = helpers.project({ lang = "es" })
        assert.same({ "Uno" }, project.get_groups("## Grupo: Uno [Implementado]\n"))
        helpers.cleanup(es)
        root = helpers.project({})
    end)

    it("finds nothing in a plan that has no groups", function()
        assert.same({}, project.get_groups("# T\n\n## Ideas\n- an idea\n"))
    end)

    it("leaves a name alone that carries no tag", function()
        assert.equals("One", project.clean_group_name("One"))
    end)
end)

describe("project.get_ideas", function()
    local root

    before_each(function()
        helpers.cleanup(root)
        root = helpers.project({})
    end)

    it("collects the ideas under a section header", function()
        local plan = "# T\n\n## Ideas\n- first\n- second\n\n## Group: A\n- grouped\n"
        assert.same({ "first", "second" }, project.get_ideas(plan, "## Ideas"))
    end)

    it("stops at the next section", function()
        local plan = "# T\n\n## Ideas\n- first\n\n## Group: A\n- grouped\n"
        assert.same({ "first" }, project.get_ideas(plan, "## Ideas"))
    end)

    it("strips the group tag an idea carries", function()
        local plan = "# T\n\n## Ideas\n- first [Group: A]\n"
        assert.same({ "first" }, project.get_ideas(plan, "## Ideas"))
    end)

    it("returns nothing for a header that is not there", function()
        assert.same({}, project.get_ideas("# T\n", "## Ideas"))
    end)
end)

describe("project.mark_group_status", function()
    local root

    before_each(function()
        helpers.cleanup(root)
        root = helpers.project({})
    end)

    it("tags a group that has no tag yet", function()
        local out = project.mark_group_status("## Group: One\n", "One", "implemented")
        assert.matches("## Group: One %[", out)
    end)

    it("replaces a tag rather than appending a second one", function()
        local once = project.mark_group_status("## Group: One\n", "One", "edited")
        local twice = project.mark_group_status(once, "One", "implemented")
        local _, count = twice:gsub("%[", "")
        assert.equals(1, count)
    end)

    it("returns nil content untouched instead of erroring", function()
        assert.is_nil(project.mark_group_status(nil, "One", "implemented"))
    end)
end)

describe("project.setup", function()
    it("resolves the root, the plan and the config from the open buffer", function()
        local root = helpers.project({ name = "Fixture" })
        assert.truthy(project.project_root:find("p", 1, true))
        assert.matches("plan%.wyt%.md$", project.section_plan_path)
        assert.matches("config%.wyt%.yml$", project.config_path)
        helpers.cleanup(root)
    end)

    it("reads the language out of the config", function()
        local root = helpers.project({ lang = "es" })
        assert.equals("es", project.lang)
        helpers.cleanup(root)
    end)
end)
