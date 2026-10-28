-- :WYTResolve answers the wyt markers, :WYTAsk answers a question. The model is
-- stubbed; what is checked is which markers are asked about, what the model is
-- given to answer from, and that only the answers the writer took land, in
-- place, with the rest of the text as it was.
local helpers = require("tests.helpers")
local project = require("wyt.project")
local resolve = require("wyt.resolve")
local llm = require("wyt.llm")
-- Put back before each spec: the runner has no after_each.
local generate_text = llm.generate_text

local ROOT_PLAN = table.concat({
    "# The Port", "", "## Description", "", "A town during a dock strike.", "",
    "## Ideas", "", "- the docks [Group: Part one]", "- who is who [Group: Characters]", "",
    "## Group: Part one [Implemented]", "- the docks", "",
    "## Group: Characters [Implemented]", "- who is who", "",
}, "\n")

local TEXT = table.concat({
    "## Group: The arrival",
    "",
    "She came on the night ferry in wyt: the year :wyt, and wyt(the sister) met her.",
    "",
    "wyt: what the gate looked like",
    "",
    "```old",
    "wyt(a parked gap)",
    "```",
    "",
}, "\n")

local function t(k) return require("wyt.localization").t(k, "en") end

local function setup_project()
    local root = helpers.project({ sections = true, name = "The Port", plan = ROOT_PLAN })
    -- A text left at a level of sub-sections is never exported: its markers are not gaps.
    helpers.write(root .. "text.wyt.md", "wyt(not a gap)\n")
    helpers.write(root .. "part-one/config.wyt.yml", "lang: en\ntype: essay\ncontent_type: content\nsections: false\nname: Part one\n")
    helpers.write(root .. "part-one/plan.wyt.md", "# Part one\n\n## Ideas\n\n- the ferry [Group: The arrival]\n\n## Group: The arrival [Implemented]\n- the ferry\n")
    helpers.write(root .. "part-one/text.wyt.md", TEXT)
    helpers.write(root .. "characters/config.wyt.yml", "lang: en\ntype: essay\ncontent_type: definition\nsections: false\nname: Characters\n")
    helpers.write(root .. "characters/plan.wyt.md", "# Characters\n\n## Group: Ines\n- the sister, a nurse\n")
    vim.system({ "git", "-C", root, "init", "-q" }):wait()
    return root
end

-- The model's replies, one per call, and the prompts it was sent.
local function replies(list)
    local prompts = {}
    llm.generate_text = function(prompt, cb)
        prompts[#prompts + 1] = prompt
        cb(table.remove(list, 1))
    end
    return prompts
end

local function answers(map)
    local out = {}
    for id, text in pairs(map) do out[#out + 1] = { id = id, text = text } end
    return vim.json.encode({ answers = out })
end

local function lines_of(path) return vim.split(helpers.read(path), "\n", { plain = true }) end

describe("resolve.files", function()
    local root
    before_each(function() helpers.cleanup(root); root = setup_project() end)

    it("takes every text in the project from a buffer that is not one", function()
        local files = resolve.files(project)
        assert.equals(1, #files)
        assert.truthy(files[1].path:find("part%-one[\\/]text%.wyt%.md$"))
        -- The parked marker is set aside, not open.
        assert.same({ "the year", "the sister", "what the gate looked like" },
            vim.tbl_map(function(m) return m.text end, files[1].markers))
    end)

    it("takes only the text on screen when it has markers", function()
        helpers.write(root .. "characters/text.wyt.md", "## Group: Ines\n\nBorn in wyt(the year).\n")
        assert.equals(2, #resolve.files(project))
        vim.cmd("edit " .. vim.fn.fnameescape(root .. "characters/text.wyt.md"))
        local files = resolve.files(project)
        assert.equals(1, #files)
        assert.truthy(files[1].path:find("characters[\\/]text%.wyt%.md$"))
    end)
end)

describe(":WYTResolve", function()
    local root
    before_each(function()
        llm.generate_text = generate_text
        helpers.cleanup(root)
        root = setup_project()
    end)

    it("asks once for every marker, from the reference, and writes what was taken", function()
        local prompts = replies({ answers({ M1 = "1931", M2 = "Ines", M3 = "It was iron.\n\nIt was chained." }) })
        local _, restore = helpers.scripted_ui({ t("resolve_use"), t("resolve_skip"), t("resolve_use") })
        local _, restore_notify = helpers.capture_notify()
        resolve.open()
        restore_notify()
        restore()

        assert.equals(1, #prompts)
        assert.matches("A town during a dock strike", prompts[1])
        assert.matches("the sister, a nurse", prompts[1])
        assert.matches("M3: what the gate looked like", prompts[1])
        -- Each marker goes with the paragraph it sits in.
        assert.matches("<paragraph>\nShe came on the night ferry", prompts[1])
        assert.has_no_match("not a gap", prompts[1])
        assert.has_no_match("a parked gap", prompts[1])
        assert.same({
            "## Group: The arrival",
            "",
            "She came on the night ferry in 1931, and wyt(the sister) met her.",
            "",
            "It was iron.",
            "",
            "It was chained.",
            "",
            "```old",
            "wyt(a parked gap)",
            "```",
            "",
        }, lines_of(root .. "part-one/text.wyt.md"))
        local r = vim.system({ "git", "-C", root, "log", "-1", "--format=%s" }, { text = true }):wait()
        assert.matches("^Save: resolved wyt markers", r.stdout)
    end)

    it("answers both markers of one line, right to left", function()
        replies({ answers({ M1 = "1931", M2 = "Ines" }) })
        local _, restore = helpers.scripted_ui({ t("resolve_use"), t("resolve_use"), nil })
        local _, restore_notify = helpers.capture_notify()
        resolve.open()
        restore_notify()
        restore()
        assert.equals("She came on the night ferry in 1931, and Ines met her.", lines_of(root .. "part-one/text.wyt.md")[3])
    end)

    it("asks again for one marker with the writer's note, and keeps the new answer", function()
        local prompts = replies({ answers({ M1 = "1931", M2 = "Ines", M3 = "A gate." }), answers({ M1 = "1932" }) })
        local _, restore = helpers.scripted_ui({ t("resolve_change"), "the year of the strike", t("resolve_use"), nil })
        local _, restore_notify = helpers.capture_notify()
        resolve.open()
        restore_notify()
        restore()
        assert.equals(2, #prompts)
        assert.matches('did not want "1931" and says: the year of the strike', prompts[2])
        assert.has_no_match("M2:", prompts[2])
        assert.matches("ferry in 1932, and", lines_of(root .. "part-one/text.wyt.md")[3])
    end)

    it("goes back to the answer on an empty note, and stops on Esc", function()
        replies({ answers({ M1 = "1931", M2 = "Ines", M3 = "A gate." }) })
        local log, restore = helpers.scripted_ui({ t("resolve_change"), "", t("resolve_use"), t("resolve_change"), nil })
        local _, restore_notify = helpers.capture_notify()
        resolve.open()
        restore_notify()
        restore()
        -- The empty note reopened the same marker's menu.
        assert.equals("select", log[3].kind)
        assert.equals(5, #log)
        -- Esc on the second note ended the run; the first answer was still written.
        local line = lines_of(root .. "part-one/text.wyt.md")[3]
        assert.equals("She came on the night ferry in 1931, and wyt(the sister) met her.", line)
    end)

    it("asks with the note alone for a marker that had no answer", function()
        local prompts = replies({ answers({ M1 = "1931" }), answers({ M2 = "Ines" }) })
        local _, restore = helpers.scripted_ui({ t("resolve_use"), t("resolve_change"), "the sister's name", t("resolve_use"), nil })
        local _, restore_notify = helpers.capture_notify()
        resolve.open()
        restore_notify()
        restore()
        assert.matches("The writer says: the sister's name", prompts[2])
        assert.has_no_match("did not want", prompts[2])
        assert.equals("She came on the night ferry in 1931, and Ines met her.", lines_of(root .. "part-one/text.wyt.md")[3])
    end)

    it("offers no Use it for a marker the model did not answer", function()
        replies({ answers({ M1 = "1931" }) })
        local log, restore = helpers.scripted_ui({ t("resolve_skip"), nil })
        local _, restore_notify = helpers.capture_notify()
        resolve.open()
        restore_notify()
        restore()
        assert.truthy(vim.tbl_contains(log[1].items, t("resolve_use")))
        assert.same({ t("resolve_skip"), t("resolve_change") }, log[2].items)
    end)

    it("keeps a CRLF text CRLF", function()
        -- Binary both ways: helpers.write and read go through text mode, which
        -- on Windows doubles a written \r and drops a read one.
        project.write_file(root .. "part-one/text.wyt.md", (TEXT:gsub("\n", "\r\n")))
        replies({ answers({ M1 = "1931" }) })
        local _, restore = helpers.scripted_ui({ t("resolve_use"), nil })
        local _, restore_notify = helpers.capture_notify()
        resolve.open()
        restore_notify()
        restore()
        local raw = project.read_file(root .. "part-one/text.wyt.md")
        assert.truthy(raw:find("ferry in 1931, and wyt%(the sister%) met her%.\r\n"))
        assert.falsy(raw:find("[^\r]\n"))
    end)

    it("leaves a marker whose line changed under it", function()
        replies({ answers({ M1 = "1931" }) })
        local ui = require("wyt.ui")
        local ask_select = ui.ask_select
        ui.ask_select = function(q, items, cb)
            helpers.write(root .. "part-one/text.wyt.md", (TEXT:gsub("night ferry", "late ferry")))
            ui.ask_select = ask_select
            cb(t("resolve_use"))
        end
        local _, restore = helpers.scripted_ui({ nil })
        local messages, restore_notify = helpers.capture_notify()
        resolve.open()
        restore_notify()
        restore()
        ui.ask_select = ask_select
        assert.matches("late ferry in wyt: the year :wyt", lines_of(root .. "part-one/text.wyt.md")[3])
        assert.truthy(vim.iter(messages):any(function(m) return m.msg == t("resolve_moved"):format(1) end))
    end)

    it("says so when there is nothing to resolve", function()
        vim.fn.delete(root .. "part-one/text.wyt.md")
        local called = false
        llm.generate_text = function() called = true end
        local messages, restore_notify = helpers.capture_notify()
        resolve.open()
        restore_notify()
        assert.falsy(called)
        assert.equals(t("resolve_none"), messages[#messages].msg)
    end)
end)

describe(":WYTAsk", function()
    local root
    before_each(function()
        llm.generate_text = generate_text
        helpers.cleanup(root)
        root = setup_project()
    end)

    it("answers from the reference and the text on screen, and never writes", function()
        vim.cmd("edit " .. vim.fn.fnameescape(root .. "part-one/text.wyt.md"))
        local before = helpers.read(root .. "part-one/text.wyt.md")
        local prompts = replies({ "## Ines\nShe is the sister.", "A nurse." })
        local log, restore = helpers.scripted_ui({ "Who is Ines?", t("ask_another"), "What does she do?", t("ask_close") })
        local _, restore_notify = helpers.capture_notify()
        require("wyt.ask").open()
        restore_notify()
        restore()

        assert.equals(2, #prompts)
        assert.matches("the sister, a nurse", prompts[1])
        assert.matches("She came on the night ferry", prompts[1])
        assert.matches("The writer asks: Who is Ines%?", prompts[1])
        assert.same({ t("ask_another"), t("ask_close") }, log[2].items)
        assert.equals(before, helpers.read(root .. "part-one/text.wyt.md"))
    end)

    it("asks again on an empty question, and nothing on Esc", function()
        local called = false
        llm.generate_text = function() called = true end
        local log, restore = helpers.scripted_ui({ "", nil })
        require("wyt.ask").open()
        restore()
        assert.equals(2, #log)
        assert.equals("input", log[2].kind)
        assert.falsy(called)
    end)
end)
