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

    -- The folder is named from this, and dropping the byte instead of folding it
    -- turned "Canción" into "cancin", a name the writer does not recognise.
    it("folds an accent onto its base letter", function()
        assert.equals("cancion", project.slugify("Canción"))
        assert.equals("el-nino-y-la-ciguena", project.slugify("El Niño y la Cigüeña"))
        assert.equals("angel", project.slugify("Ángel"))
    end)

    it("returns the slug alone, not gsub's count with it", function()
        assert.equals(1, select("#", project.slugify("Canción")))
    end)
end)

describe("project.group_dir", function()
    it("is nil for a name that slugifies to nothing", function()
        local root = helpers.project()
        assert.is_nil(project.group_dir(root, "!!!"))
        helpers.cleanup(root)
    end)

    it("finds the folder named from the group", function()
        local root = helpers.project()
        helpers.write(root .. "cancion/plan.wyt.md", "# Canción\n")
        assert.equals(root .. "cancion/", project.group_dir(root, "Canción"))
        helpers.cleanup(root)
    end)

    -- A section created before accents were folded is on disk under the stripped
    -- spelling. Looking only for the new slug would drop it out of the export,
    -- :WYTNav and :WYTSearch without a word.
    it("falls back to the folder an older WYT would have made", function()
        local root = helpers.project()
        helpers.write(root .. "cancin/plan.wyt.md", "# Canción\n")
        assert.equals(root .. "cancin/", project.group_dir(root, "Canción"))
        helpers.cleanup(root)
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

    it("falls back to the project's Description inside a section", function()
        local root = helpers.project({ type = "novel", description = "A city that forgets." })
        -- A section plan is written as a title and Ideas, with no Description.
        local ctx = project.description_context("# Chapter One\n\n## Ideas\n")
        assert.equals("Novel. A city that forgets.", ctx)
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

describe("project root detection on Windows", function()
    -- With 'shellslash' a buffer name arrives with "/", while package.config
    -- still says "\": matching only that separator found no root at all.
    it("finds the root from a buffer named with forward slashes", function()
        if vim.fn.has("win32") == 0 then return end
        local shellslash = vim.o.shellslash
        vim.o.shellslash = true
        local ok, err = pcall(function()
            local root = helpers.project({ name = "Fixture" })
            assert.matches("/plan%.wyt%.md$", vim.api.nvim_buf_get_name(0))
            local norm = function(p) return (p:gsub("\\", "/")) end
            assert.equals(norm(root), norm(project.project_root))
            helpers.cleanup(root)
        end)
        vim.o.shellslash = shellslash
        assert(ok, err)
    end)
end)

describe("project.setup", function()
    it("resolves the root, the plan and the config from the open buffer", function()
        local root = helpers.project({ name = "Fixture" })
        local norm = function(p) return (p:gsub("\\", "/")) end
        assert.equals(norm(root), norm(project.project_root))
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

describe("project.implement_group", function()
    -- Without a slug the section folder is the parent itself: its plan gets
    -- renamed to plan.old.wyt.md and rewritten with the group's own ideas.
    it("refuses a group name that leaves nothing to name a folder with", function()
        local root = helpers.project({ type = "novel", name = "A City" })
        local before = project.read_file(root .. "plan.wyt.md")
        local name = string.char(0xC2, 0xAB) .. string.char(0xC2, 0xBB)
        local messages, restore = helpers.capture_notify()
        local ran = false
        project.implement_group(before .. "\n## Group: " .. name .. "\n", name, root, true,
            function() ran = true end)
        restore()
        assert.falsy(ran)
        assert.is_nil(project.read_file(root .. "plan.old.wyt.md"))
        assert.equals(before, project.read_file(root .. "plan.wyt.md"))
        assert.equals(1, #messages)
        assert.matches(name, messages[1].msg, 1, true)
        helpers.cleanup(root)
    end)
end)

describe("project.normalize_path", function()
    it("expands ~ into an absolute path", function()
        local home = vim.fs.normalize(vim.fn.expand("~"))
        assert.equals(home .. "/writing", project.normalize_path("~/writing"))
    end)

    -- vim.fn.expand() runs a backtick expression through the shell, and this
    -- string is whatever was typed at the wizard's prompt.
    it("leaves a backtick expression as a literal folder name", function()
        local out = project.normalize_path("`echo hacked`")
        assert.matches("/`echo hacked`$", out, 1, true)
    end)

    it("takes the trailing separator off", function()
        assert.has_no_match("/$", project.normalize_path(vim.fn.getcwd() .. "/"))
    end)
end)

describe("project.config_value", function()
    -- WYT writes every scalar bare, but the config is a file the writer edits by
    -- hand, and YAML lets the value be quoted. Reading `type: "novel"` as no
    -- type at all sent the whole project back to the essay outline.
    it("reads a quoted value", function()
        assert.equals("novel", project.config_value('type: "novel"', "type"))
        assert.equals("es", project.config_value("lang: 'es'", "lang"))
    end)

    it("reads a bare value", function()
        assert.equals("short_story", project.config_value("type: short_story", "type"))
    end)

    it("does not read `type` off the end of `content_type`", function()
        assert.equals("novel", project.config_value("content_type: definition\ntype: novel", "type"))
        assert.equals("definition", project.config_value("content_type: definition", "content_type"))
    end)

    it("is nil for a missing or empty key", function()
        assert.is_nil(project.config_value("lang: en", "type"))
        assert.is_nil(project.config_value("type:", "type"))
    end)
end)

describe("project.enclosing_project", function()
    it("finds the project a folder sits inside", function()
        local root = helpers.project()
        assert.equals(root:sub(1, -2), project.enclosing_project(root .. "notes"))
        helpers.cleanup(root)
    end)

    it("is nil outside any project", function()
        assert.is_nil(project.enclosing_project(vim.fn.tempname() .. "/elsewhere"))
    end)
end)

describe("project.new_project", function()
    -- Esc is a cancel and Enter on a blank name is not, so the wizard asks
    -- again rather than throwing away the three answers already given.
    it("asks for the name again when it comes back empty", function()
        local base = vim.fn.tempname()
        vim.fn.mkdir(base, "p")
        local _, restore_notify = helpers.capture_notify()
        local log, restore_ui = helpers.scripted_ui({ "en", "short_story", base, "", "A Piece", nil })
        project.new_project()

        assert.equals(6, #log)
        assert.equals(log[4].prompt, log[5].prompt)
        assert.equals(0, #vim.fn.readdir(base))
        restore_ui(); restore_notify()
        vim.fn.delete(base, "rf")
    end)

    -- The root walk takes the outermost project, so a project created inside
    -- another one is read as a section of it.
    it("asks before creating a project inside another one", function()
        local outer = helpers.project()
        notes, restore_notify = helpers.capture_notify()
        local loc = require("wyt.localization")
        log, restore_ui = helpers.scripted_ui({ "en", "short_story", outer, "Inner", "inner", loc.t("no", "en") })
        project.new_project()

        -- The long warning goes in a panel, so the menu prompt is its title.
        assert.equals(loc.t("nested_project_title", "en"), log[#log].prompt)
        assert.same({ loc.t("yes", "en"), loc.t("no", "en") }, log[#log].items)
        assert.is_nil((vim.uv or vim.loop).fs_stat(outer .. "inner/config.wyt.yml"))
        restore_ui(); restore_notify()
        helpers.cleanup(outer)
    end)
end)
