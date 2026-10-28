-- :WYTOutline shows the project as the export walks it. What is checked is the
-- rows (order, nesting, what is open in each), and that the sidebar opens the
-- right file at the right line and keeps up with saves.
local helpers = require("tests.helpers")
local project = require("wyt.project")
local outline = require("wyt.outline")

local ROOT_PLAN = table.concat({
    "# The Port", "", "## Description", "", "A town during a dock strike.", "",
    "## Ideas", "", "- the docks [Group: Part one]", "- a loose idea", "",
    "## Group: Part one [Implemented]", "- the docks", "",
    "## Group: Part two", "- the end", "",
}, "\n")

local PART_PLAN = table.concat({
    "# Part one", "", "## Ideas", "",
    "- the ferry [Group: The arrival]", "- the hall [Group: The strike]", "",
    "## Group: The arrival [Implemented]", "- the ferry", "",
    "## Group: The strike [Implemented]", "- the hall", "",
    "## Group: The gate", "- a chain", "",
}, "\n")

local PART_TEXT = table.concat({
    "## Group: The arrival", "",
    "She came on the night ferry.", "",
    "*Create a paragraph about: [the harbour master]*", "",
    "*Create a paragraph about: [the fog]*", "",
    "## Group: The strike", "",
    "Nobody unloaded anything that week.", "",
}, "\n")

local function t(k) return require("wyt.localization").t(k, "en") end

local function setup_project()
    local root = helpers.project({ sections = true, name = "The Port", plan = ROOT_PLAN })
    helpers.write(root .. "part-one/config.wyt.yml", "lang: en\ntype: essay\ncontent_type: content\nsections: false\nname: Part one\n")
    helpers.write(root .. "part-one/plan.wyt.md", PART_PLAN)
    helpers.write(root .. "part-one/text.wyt.md", PART_TEXT)
    helpers.write(root .. "freewrite/2026-01-01-0900.md", "Loose words.\n")
    vim.system({ "git", "-C", root, "init", "-q" }):wait()
    return root
end

local function sidebar()
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == "wytoutline" then return w end
    end
end

describe("outline.rows", function()
    local root
    before_each(function() helpers.cleanup(root); root = setup_project() end)

    it("walks sections and their groups in plan order, with what is open in each", function()
        local got = vim.tbl_map(function(r) return { r.text, r.count } end, outline.rows(project))
        assert.same({
            -- One ungrouped idea, Part two never implemented, and all of Part one.
            { "The Port", 5 },
            -- Two placeholders and The gate still to write.
            { "  Part one", 3 },
            { "    The arrival", 2 },
            { "    The strike", 0 },
            { "    ○ The gate", 0 },
            -- After Part one, where the plan puts it.
            { "  ○ Part two", 0 },
            { t("outline_freewrite"), 1 },
        }, got)
    end)

    it("points each row at the file and line it stands for", function()
        local rows = outline.rows(project)
        -- A level of sub-sections has no text: it opens its plan.
        assert.truthy(vim.endswith(rows[1].path, "plan.wyt.md"))
        assert.truthy(rows[6].planned)
        assert.equals(15, rows[6].line)
        assert.truthy(rows[2].path:find("part%-one[\\/]text%.wyt%.md$"))
        assert.equals(9, rows[4].line)
        assert.truthy(rows[5].path:find("part%-one[\\/]plan%.wyt%.md$"))
    end)

    it("leaves out a group parked in an old fence", function()
        helpers.write(root .. "part-one/text.wyt.md", PART_TEXT .. "```old\n## Group: The pier\n\n*Create a paragraph about: [a dog]*\n```\n")
        local texts = vim.tbl_map(function(r) return r.text end, outline.rows(project))
        assert.falsy(vim.tbl_contains(texts, "    The pier"))
    end)
end)

describe(":WYTOutline", function()
    local root
    -- Every spec starts from one window and no buffers: a file left open by the
    -- last one would decide where `wincmd p` and the main window land.
    before_each(function()
        vim.cmd("tabnew")
        vim.cmd("tabonly")
        vim.cmd("silent! %bwipeout!")
        helpers.cleanup(root)
        root = setup_project()
        vim.cmd("edit " .. vim.fn.fnameescape(root .. "plan.wyt.md"))
    end)

    it("opens a sidebar of the rows, and closes on q", function()
        outline.toggle()
        assert.equals("wytoutline", vim.bo.filetype)
        assert.equals(32, vim.api.nvim_win_get_width(0))
        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        assert.matches("^    The arrival +2$", lines[3])
        assert.equals(t("outline_keys"), lines[#lines])
        vim.api.nvim_feedkeys("q", "x", false)
        assert.falsy(vim.bo.filetype == "wytoutline")
    end)

    it("opens a group's text at its line, in the window beside it", function()
        outline.toggle()
        local sidebar = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_cursor(0, { 4, 0 })
        vim.api.nvim_feedkeys("\r", "x", false)
        assert.falsy(vim.api.nvim_get_current_win() == sidebar)
        assert.truthy(vim.api.nvim_buf_get_name(0):find("part%-one[\\/]text%.wyt%.md$"))
        assert.equals(9, vim.api.nvim_win_get_cursor(0)[1])
        assert.truthy(vim.api.nvim_win_is_valid(sidebar))
    end)

    it("opens a planned group's plan at its line", function()
        outline.toggle()
        vim.api.nvim_win_set_cursor(0, { 6, 0 })
        vim.api.nvim_feedkeys("\r", "x", false)
        assert.truthy(vim.endswith(vim.api.nvim_buf_get_name(0), "plan.wyt.md"))
        assert.equals("## Group: Part two", vim.api.nvim_get_current_line())
    end)

    it("leaves the freewrite row out when nothing waits", function()
        vim.fn.delete(root .. "freewrite", "rf")
        local rows = outline.rows(project)
        assert.falsy(rows[#rows].freewrite)
    end)

    it("opens the newest freewrite before placing it", function()
        helpers.write(root .. "freewrite/2026-01-02-0900.md", "Later words.\n")
        local place = require("wyt.place")
        local open, got = place.open, nil
        place.open = function() got = vim.api.nvim_buf_get_name(0) end
        outline.toggle()
        vim.api.nvim_win_set_cursor(0, { #outline.rows(project), 0 })
        vim.api.nvim_feedkeys("\r", "x", false)
        place.open = open
        assert.truthy(got and got:find("2026%-01%-02%-0900%.md$"), got)
    end)

    it("opens the plan of the row on p", function()
        outline.toggle()
        vim.api.nvim_win_set_cursor(0, { 3, 0 })
        vim.api.nvim_feedkeys("p", "x", false)
        assert.truthy(vim.api.nvim_buf_get_name(0):find("part%-one[\\/]plan%.wyt%.md$"))
    end)

    it("catches up after a save", function()
        require("wyt.autocmd").setup()
        outline.toggle()
        vim.cmd("wincmd p")
        vim.cmd("edit " .. vim.fn.fnameescape(root .. "part-one/text.wyt.md"))
        vim.api.nvim_buf_set_lines(0, 4, 5, false, { "The harbour master had the key." })
        vim.cmd("silent write")
        local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(sidebar()), 0, -1, false)
        assert.matches("^    The arrival +1$", lines[3])
    end)

    it("still catches up when the two roots differ only in their separators", function()
        require("wyt.autocmd").setup()
        -- Opened from no buffer, the root comes from the cwd ("D:\x/" on
        -- Windows); the save then resolves it from a buffer ("D:\x\").
        local cwd = vim.fn.getcwd()
        vim.cmd("enew")
        vim.cmd("cd " .. vim.fn.fnameescape(root))
        outline.toggle()
        vim.cmd("cd " .. vim.fn.fnameescape(cwd))
        vim.cmd("wincmd p")
        vim.cmd("edit " .. vim.fn.fnameescape(root .. "part-one/text.wyt.md"))
        vim.api.nvim_buf_set_lines(0, 4, 5, false, { "The harbour master had the key." })
        vim.cmd("silent write")
        local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(sidebar()), 0, -1, false)
        assert.matches("^    The arrival +1$", lines[3])
    end)

    it("keeps its window options to itself", function()
        outline.toggle()
        assert.falsy(vim.wo.number)
        vim.cmd("wincmd p")
        vim.cmd("vnew")
        assert.equals(vim.go.wrap, vim.wo.wrap)
        assert.falsy(vim.wo.winfixwidth)
        assert.falsy(vim.wo.winfixbuf)
    end)

    it("will not load a file into the sidebar", function()
        outline.toggle()
        assert.falsy(pcall(vim.cmd, "edit " .. vim.fn.fnameescape(root .. "plan.wyt.md")))
        assert.equals("wytoutline", vim.bo.filetype)
    end)

    it("closes when it is the last window, leaving a plain one", function()
        outline.toggle()
        vim.cmd("only")
        vim.api.nvim_feedkeys("q", "x", false)
        assert.falsy(sidebar())
        assert.equals(1, #vim.api.nvim_tabpage_list_wins(0))
        assert.falsy(vim.wo.winfixbuf)
    end)
end)

describe("outline.rows and wyt markers", function()
    local root
    before_each(function() helpers.cleanup(root); root = setup_project() end)

    it("counts a marker as open, in its group and every section above it", function()
        helpers.write(root .. "part-one/text.wyt.md",
            (PART_TEXT:gsub("Nobody unloaded", "In wyt(the year), nobody unloaded")))
        local got = vim.tbl_map(function(r) return { r.text, r.count } end, outline.rows(project))
        assert.same({ "The Port", 6 }, got[1])
        assert.same({ "  Part one", 4 }, got[2])
        assert.same({ "    The strike", 1 }, got[4])
    end)
end)
