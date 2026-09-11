-- export.lua assembles the finished document from what is on disk. It never
-- calls the LLM, so these run end to end: build a real tree, export it, read
-- the file back. What each type's outline does to a section name is the point.
local helpers = require("tests.helpers")
local project = require("wyt.project")

-- A section exists for the export only if its parent's plan names it as a group:
-- the walk follows group names, slugified, and never lists the directory. So a
-- fixture has to add the group above and the folder below, and the heading the
-- reader sees comes from the parent's plan, not from the section's own title.
--
-- `parent` is "" for a section of the project root.
local function section(root, parent, name, opts)
    opts = opts or {}
    local parent_plan = root .. parent .. "plan.wyt.md"
    helpers.write(parent_plan, (helpers.read(parent_plan) or "") .. "\n## Group: " .. name .. "\n")

    local dir = root .. parent .. require("wyt.project").slugify(name) .. "/"
    helpers.write(dir .. "config.wyt.yml", string.format(
        "lang: %s\ntype: %s\ncontent_type: %s\nsections: %s\n",
        opts.lang or "en", opts.type or "essay",
        opts.content_type or "content", tostring(opts.sections or false)))
    helpers.write(dir .. "plan.wyt.md", "# " .. name .. "\n")
    if opts.text then helpers.write(dir .. "text.wyt.md", opts.text) end
    return dir
end

local function export_of(root)
    local notify_restore = select(2, helpers.capture_notify())
    -- The export opens the file it wrote; keep that out of the fixture buffer.
    local ui = require("wyt.ui")
    local edit = ui.edit_file
    ui.edit_file = function() end
    require("wyt.export").export()
    ui.edit_file = edit
    notify_restore()
    return helpers.read(root .. "export.wyt.md")
end

describe("export by type", function()
    local root

    before_each(function() helpers.cleanup(root) end)

    it("titles an essay's sections and runs their paragraphs on", function()
        root = helpers.project({ type = "essay", name = "On Cities" })
        section(root, "", "Density", { type = "essay", text = "Density is a choice.\n" })
        section(root, "", "Silence", { type = "essay", text = "Silence is engineered.\n" })
        local out = export_of(root)
        assert.matches("^# On Cities", out)
        assert.matches("## Density", out)
        assert.matches("## Silence", out)
        assert.has_no_match("%* %* %*", out)
    end)

    it("titles a novel's chapters and separates the scenes below them", function()
        root = helpers.project({ type = "novel", name = "A City" })
        section(root, "", "Chapter One", { type = "novel", sections = true })
        section(root, "chapter-one/", "Scene A", { type = "novel", text = "The platform was empty.\n" })
        section(root, "chapter-one/", "Scene B", { type = "novel", text = "The train did not come.\n" })
        local out = export_of(root)
        assert.matches("## Chapter One", out)
        assert.matches("%* %* %*", out)
        -- Level 3 is a scene break, so neither scene name is printed.
        assert.has_no_match("Scene A", out)
        assert.has_no_match("Scene B", out)
    end)

    it("never titles a short novel's scenes", function()
        root = helpers.project({ type = "short_novel", name = "A Week" })
        section(root, "", "Monday", { type = "short_novel", text = "It rained.\n" })
        section(root, "", "Tuesday", { type = "short_novel", text = "It stopped.\n" })
        local out = export_of(root)
        assert.has_no_match("Monday", out)
        assert.matches("%* %* %*", out)
        assert.matches("It rained%.", out)
    end)

    it("turns a summary's group names into headings", function()
        root = helpers.project({ type = "summary", name = "Notes", sections = false })
        helpers.write(root .. "text.wyt.md",
            "## Group: Decisions\n\nWe ship on Friday.\n\n## Group: Risks\n\nThe API may change.\n")
        local out = export_of(root)
        assert.matches("## Decisions", out)
        assert.matches("## Risks", out)
    end)

    it("separates a short story's groups instead of naming them", function()
        root = helpers.project({ type = "short_story", name = "The Platform", sections = false })
        helpers.write(root .. "text.wyt.md",
            "## Group: Setup\n\nHe waited.\n\n## Group: Turn\n\nShe did not come.\n")
        local out = export_of(root)
        assert.has_no_match("Setup", out)
        assert.matches("%* %* %*", out)
        assert.matches("He waited%.", out)
    end)
end)

describe("what the export leaves out", function()
    local root

    before_each(function() helpers.cleanup(root) end)

    it("excludes a definition section, which is reference and not text", function()
        root = helpers.project({ type = "novel", name = "A City" })
        section(root, "", "Chapter One", { type = "novel", text = "The platform was empty.\n" })
        section(root, "", "Cast", { type = "novel", content_type = "definition",
            text = "Ana is afraid of trains.\n" })
        local out = export_of(root)
        assert.matches("The platform was empty%.", out)
        assert.has_no_match("Ana is afraid", out)
        assert.has_no_match("Cast", out)
    end)

    it("drops a group whose paragraphs are all still placeholders", function()
        root = helpers.project({ type = "summary", name = "Notes", sections = false })
        helpers.write(root .. "text.wyt.md",
            "## Group: Written\n\nWe ship on Friday.\n\n## Group: Empty\n\n")
        local out = export_of(root)
        assert.matches("## Written", out)
        assert.has_no_match("Empty", out)
    end)

    it("produces just the title for a project with nothing written", function()
        root = helpers.project({ type = "essay", name = "Empty" })
        assert.equals("# Empty", vim.trim(export_of(root)))
    end)
end)

describe("a branch nested past its type's outline", function()
    it("comes out untitled rather than breaking the export", function()
        local root = helpers.project({ type = "essay", name = "On Cities" })
        -- essay maps level 2 only; this section's own `sections: true` is the
        -- per-section override, so its child sits at level 3, past the map.
        section(root, "", "Density", { type = "essay", sections = true })
        section(root, "density/", "Deeper", { type = "essay", text = "The third level speaks.\n" })
        section(root, "", "Silence", { type = "essay", text = "The second level speaks.\n" })
        local out = export_of(root)
        assert.matches("## Density", out)
        assert.matches("## Silence", out)
        assert.matches("The third level speaks%.", out)
        assert.has_no_match("Deeper", out)
        assert.has_no_match("### ", out)
        helpers.cleanup(root)
    end)
end)

describe("the export is written where WYTGoto export looks for it", function()
    it("lands at the project root, whatever section was open", function()
        local root = helpers.project({ type = "essay", name = "On Cities" })
        section(root, "", "Density", { type = "essay", text = "Density is a choice.\n" })
        export_of(root)
        assert.is_not_nil(helpers.read(root .. "export.wyt.md"))
        assert.is_nil(helpers.read(root .. "density/export.wyt.md"))
        helpers.cleanup(root)
    end)

    it("takes its title from the root plan's first heading", function()
        local root = helpers.project({ type = "essay", name = "On Cities" })
        assert.matches("^# On Cities", export_of(root))
        helpers.cleanup(root)
    end)
end)
