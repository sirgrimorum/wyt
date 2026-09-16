-- nav.lua and search.lua both walk the section tree the same way: by group name
-- from each plan, not by listing directories. They are tested together because
-- a change to that walk breaks both, and the fixture is the same tree.
local helpers = require("tests.helpers")
local project = require("wyt.project")

local function section(root, parent, name, opts)
    opts = opts or {}
    local parent_plan = root .. parent .. "plan.wyt.md"
    helpers.write(parent_plan, (helpers.read(parent_plan) or "") .. "\n## Group: " .. name .. "\n")
    local dir = root .. parent .. project.slugify(name) .. "/"
    helpers.write(dir .. "config.wyt.yml", string.format(
        "lang: en\ntype: %s\ncontent_type: %s\nsections: %s\n",
        opts.type or "novel", opts.content_type or "content", tostring(opts.sections or false)))
    helpers.write(dir .. "plan.wyt.md", "# " .. name .. "\n")
    if opts.text then helpers.write(dir .. "text.wyt.md", opts.text) end
    return dir
end

-- navigate() ends in a select over plain label strings; capture what it offered.
local function nav_labels()
    local shown
    local original = vim.ui.select
    vim.ui.select = function(items) shown = items end
    require("wyt.nav").navigate()
    vim.ui.select = original
    return shown or {}
end

describe("nav.navigate", function()
    local root

    before_each(function() helpers.cleanup(root) end)

    -- A name with no ASCII letter or digit slugifies to "", which used to make
    -- the section folder the parent itself and the walk endless.
    it("skips a group whose name leaves nothing to name a folder with", function()
        root = helpers.project({ type = "novel", name = "A City" })
        helpers.write(root .. "plan.wyt.md",
            helpers.read(root .. "plan.wyt.md") .. "\n## Group: " .. string.char(0xC2, 0xAB) .. string.char(0xC2, 0xBB) .. "\n")
        local labels = nav_labels()
        -- The root's own two files and nothing else: no "/" folder row for a
        -- section that cannot exist.
        assert.same({ "plan.wyt.md", "config.wyt.yml" }, labels)
    end)

    it("lists the root's own files before anything nested", function()
        root = helpers.project({ type = "novel", name = "A City" })
        local labels = nav_labels()
        assert.equals("plan.wyt.md", labels[1])
        assert.truthy(vim.tbl_contains(labels, "config.wyt.yml"))
    end)

    it("indents a section's files two spaces under its folder", function()
        root = helpers.project({ type = "novel", name = "A City" })
        section(root, "", "Chapter One", { type = "novel", text = "Text.\n" })
        local labels = nav_labels()
        assert.truthy(vim.tbl_contains(labels, "chapter-one/"))
        assert.truthy(vim.tbl_contains(labels, "  plan.wyt.md"))
        assert.truthy(vim.tbl_contains(labels, "  text.wyt.md"))
    end)

    it("walks in plan order, not alphabetical order", function()
        root = helpers.project({ type = "novel", name = "A City" })
        section(root, "", "Zulu", { type = "novel" })
        section(root, "", "Alpha", { type = "novel" })
        local labels = nav_labels()
        local zulu, alpha
        for i, label in ipairs(labels) do
            if label == "zulu/" then zulu = i end
            if label == "alpha/" then alpha = i end
        end
        assert.truthy(zulu < alpha, "plan order should put zulu first")
    end)

    it("indents a third level four spaces", function()
        root = helpers.project({ type = "novel", name = "A City" })
        section(root, "", "Chapter One", { type = "novel", sections = true })
        section(root, "chapter-one/", "Scene A", { type = "novel", text = "Text.\n" })
        local labels = nav_labels()
        assert.truthy(vim.tbl_contains(labels, "  scene-a/"))
        assert.truthy(vim.tbl_contains(labels, "    plan.wyt.md"))
    end)

    it("skips a folder the plan does not name as a group", function()
        root = helpers.project({ type = "novel", name = "A City" })
        helpers.write(root .. "orphan/plan.wyt.md", "# Orphan\n")
        assert.falsy(vim.tbl_contains(nav_labels(), "orphan/"))
    end)
end)

describe("search collects only definition sections", function()
    local root

    before_each(function() helpers.cleanup(root) end)

    -- search() asks for the query first, then offers the hits. Both prompts are
    -- scripted; the hit labels are what says which files were searched.
    local function hits_for(query)
        local log, restore_ui = helpers.scripted_ui({ query, nil })
        local messages, restore_notify = helpers.capture_notify()
        require("wyt.search").search()
        restore_ui()
        restore_notify()
        for _, entry in ipairs(log) do
            if entry.kind == "select" then return entry.items, messages end
        end
        return {}, messages
    end

    it("finds a hit in a definition section", function()
        root = helpers.project({ type = "novel", name = "A City" })
        section(root, "", "Cast", { type = "novel", content_type = "definition",
            text = "Ana is afraid of trains.\n" })
        assert.matches("cast", vim.inspect(hits_for("afraid")))
    end)

    it("ignores a content section, which is text and not reference", function()
        root = helpers.project({ type = "novel", name = "A City" })
        section(root, "", "Chapter One", { type = "novel", text = "The platform was empty.\n" })
        local items, messages = hits_for("platform")
        assert.same({}, items)
        -- The specific message: any early exit ("no project") also shows no hits.
        assert.equals(require("wyt.localization").t("no_definitions_found", "en"),
            messages[#messages] and messages[#messages].msg)
    end)

    it("reaches a definition section nested inside a content one", function()
        root = helpers.project({ type = "novel", name = "A City" })
        section(root, "", "Chapter One", { type = "novel", sections = true })
        section(root, "chapter-one/", "Cast", { type = "novel", content_type = "definition",
            text = "Ana is afraid.\n" })
        assert.matches("cast", vim.inspect(hits_for("afraid")))
    end)

    it("labels a hit with the heading it sits under", function()
        root = helpers.project({ type = "novel", name = "A City" })
        section(root, "", "Cast", { type = "novel", content_type = "definition",
            text = "## Group: Ana\n\nafraid of trains\n" })
        assert.matches("%(Ana%)", vim.inspect(hits_for("afraid")))
    end)
end)
