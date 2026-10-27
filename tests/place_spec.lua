-- :WYTPlace moves the writer's own paragraphs out of a freewrite into the
-- project. The model is stubbed with scripted replies; what is checked is
-- where the words land, that they land unchanged, and what stays behind.
local helpers = require("tests.helpers")
local project = require("wyt.project")
local place = require("wyt.place")
local llm = require("wyt.llm")

local TEXT = table.concat({
    "## Group: The arrival",
    "",
    "She came on the night ferry.",
    "",
    "*Create a paragraph about: [the harbour master]*",
    "",
    "## Group: The strike",
    "",
    "Nobody unloaded anything that week.",
    "",
}, "\n")

local PLAN = table.concat({
    "# The Port", "", "## Description", "", "A town during a dock strike.", "",
    "## Ideas", "", "- the harbour master [Group: The arrival]", "- the union hall [Group: The strike]", "",
    "## Group: The arrival [Implemented]", "- the harbour master", "",
    "## Group: The strike [Implemented]", "- the union hall", "",
}, "\n")

local FREEWRITE = table.concat({
    "> Who opens the gate?",
    "",
    "The harbour master had the only key.",
    "",
    "The gate was chained.",
    "A man in a grey coat watched it.",
    "",
    "Maybe the dog belongs to someone.",
    "",
}, "\n")

local function t(k) return require("wyt.localization").t(k, "en") end

-- The ids are handed out in plan order, so a spec asks for one by its label.
local function id_of(label)
    for _, target in ipairs(place.targets(project)) do
        if target.label == label then return target.id end
    end
    error("no target " .. label)
end

local function replies(list)
    local prompts = {}
    llm.generate_text = function(prompt, cb)
        prompts[#prompts + 1] = prompt
        cb(table.remove(list, 1))
    end
    return prompts
end

local function setup_project()
    local root = helpers.project({ sections = false, name = "The Port", plan = PLAN })
    helpers.write(root .. "text.wyt.md", TEXT)
    vim.fn.mkdir(root .. "freewrite", "p")
    helpers.write(root .. "freewrite/2026-01-01-0900.md", FREEWRITE)
    vim.system({ "git", "-C", root, "init", "-q" }):wait()
    return root
end

describe("place.paragraphs", function()
    it("splits on blank lines and leaves the prompt out", function()
        assert.same({
            "The harbour master had the only key.",
            "The gate was chained.\nA man in a grey coat watched it.",
            "Maybe the dog belongs to someone.",
        }, place.paragraphs(FREEWRITE))
    end)

    it("keeps a quote the writer typed further down", function()
        assert.same({ "Text.", "> a quote" }, place.paragraphs("Text.\n\n> a quote\n"))
        assert.equals("> Who opens the gate?", select(2, place.paragraphs(FREEWRITE)))
        -- Not on the first line, a quote is the writer's own: kept, never dropped.
        assert.same({ "> late", "Text." }, place.paragraphs("\n> late\n\nText.\n"))
    end)
end)

describe("place.targets", function()
    local root
    before_each(function() helpers.cleanup(root); root = setup_project() end)

    it("offers the end of each group, each placeholder and the plan's ideas", function()
        local labels = {}
        for _, target in ipairs(place.targets(project)) do labels[#labels + 1] = target.label end
        assert.same({
            "After: The Port › The arrival",
            "New idea in: The Port › The arrival",
            "After: The Port › The strike",
            "New idea in: The Port › The strike",
            "Write: the harbour master (The Port)",
            "New group in: The Port",
            "Idea in: The Port",
        }, labels)
    end)
end)

describe("place.chunks", function()
    it("drops a new idea or group the model gave no name", function()
        local by_id = { T1 = { kind = "new_idea" }, T2 = { kind = "new_group" } }
        local got = place.chunks({
            { paragraphs = { 1 }, target = "T1" },
            { paragraphs = { 2 }, target = "T2", idea = "a gate" },
            { paragraphs = { 3 }, target = "T2", idea = "a gate", group = "The gate" },
        }, { 1, 2, 3 }, by_id)
        assert.same({ { 1, 2 }, { 3 } }, { got[1].paragraphs, got[2].paragraphs })
        assert.is_nil(got[1].target)
        assert.equals("The gate", got[2].group)
    end)

    it("drops unknown targets and paragraphs taken twice or out of range", function()
        local by_id = { T1 = { id = "T1" } }
        local got = place.chunks({
            { paragraphs = { 3 }, target = "keep" },
            { paragraphs = { 2, 1 }, target = "T1" },
            { paragraphs = { 1, 9 }, target = "T1" },
            { paragraphs = { 4 }, target = "T7" },
        }, { 1, 2, 3, 4 }, by_id)
        -- 4 went to no known place: it comes back kept, not lost.
        assert.same({ { 1, 2 }, { 3 }, { 4 } }, { got[1].paragraphs, got[2].paragraphs, got[3].paragraphs })
        assert.equals(by_id.T1, got[1].target)
        assert.is_nil(got[2].target)
        assert.is_nil(got[3].target)
    end)

    it("is no proposal at all when nothing in the reply is usable", function()
        assert.same({}, place.chunks({ { paragraphs = { 1 }, target = "T9" } }, { 1, 2 }, {}))
    end)
end)

describe(":WYTPlace", function()
    local root
    before_each(function() helpers.cleanup(root); root = setup_project() end)

    local function run_on_freewrite()
        vim.cmd("edit " .. vim.fn.fnameescape(root .. "freewrite/2026-01-01-0900.md"))
        place.open()
    end

    it("moves each confirmed chunk unchanged and keeps the rest in the freewrite", function()
        local reply = vim.json.encode({ chunks = {
            { paragraphs = { 1 }, target = id_of("Write: the harbour master (The Port)"), why = "It is about him." },
            { paragraphs = { 2 }, target = id_of("After: The Port › The arrival") },
            { paragraphs = { 3 }, target = id_of("Idea in: The Port") },
        } })
        local prompts = replies({ reply })
        local _, restore = helpers.scripted_ui({ t("place_it"), t("place_it"), t("place_leave") })
        run_on_freewrite()
        restore()

        assert.matches("%[1%] The harbour master had the only key%.", prompts[1])
        assert.same({
            "## Group: The arrival",
            "",
            "She came on the night ferry.",
            "",
            -- The filled placeholder is the group's last prose by then.
            "The harbour master had the only key.",
            "",
            "The gate was chained.",
            "A man in a grey coat watched it.",
            "",
            "## Group: The strike",
            "",
            "Nobody unloaded anything that week.",
            "",
        }, vim.split(helpers.read(root .. "text.wyt.md"), "\n", { plain = true }))
        assert.equals("> Who opens the gate?\n\nMaybe the dog belongs to someone.\n",
            helpers.read(root .. "freewrite/2026-01-01-0900.md"))
        local r = vim.system({ "git", "-C", root, "log", "-1", "--format=%s" }, { text = true }):wait()
        assert.matches("^Save: placed freewrite/2026%-01%-01%-0900%.md", r.stdout)
    end)

    it("adds a chunk to the plan's ideas as one line, and deletes an emptied freewrite", function()
        local idea = id_of("Idea in: The Port")
        replies({ vim.json.encode({ chunks = { { paragraphs = { 1, 2, 3 }, target = idea } } }) })
        local _, restore = helpers.scripted_ui({ t("place_it") })
        run_on_freewrite()
        restore()

        assert.matches("\n%- The harbour master had the only key%. The gate was chained%. A man",
            helpers.read(root .. "plan.wyt.md"))
        assert.is_nil((vim.uv or vim.loop).fs_stat(root .. "freewrite/2026-01-01-0900.md"))
    end)

    it("offers no text home where the level holds sub-sections", function()
        helpers.write(root .. "config.wyt.yml", "lang: en\ntype: essay\ncontent_type: content\nsections: true\nname: The Port\n")
        local labels = vim.tbl_map(function(target) return target.label end, place.targets(project))
        assert.same({ "New group in: The Port", "Idea in: The Port" }, labels)
    end)

    it("never places into a group parked in an old fence", function()
        helpers.write(root .. "text.wyt.md", TEXT .. "```old\n## Group: The pier\n\n*Create a paragraph about: [a dog]*\n```")
        local labels = vim.tbl_map(function(target) return target.label end, place.targets(project))
        assert.falsy(vim.tbl_contains(labels, "After: The Port › The pier"))
        assert.falsy(vim.tbl_contains(labels, "Write: a dog (The Port)"))

        replies({ vim.json.encode({ chunks = { { paragraphs = { 2 }, target = id_of("After: The Port › The strike") } } }) })
        local _, restore = helpers.scripted_ui({ t("place_leave"), t("place_it") })
        run_on_freewrite()
        restore()
        assert.matches("A man in a grey coat watched it%.\n```old\n", helpers.read(root .. "text.wyt.md"))
    end)

    it("locks the freewrite while the run is open, and unlocks it on every way out", function()
        local locked
        llm.generate_text = function(_, cb)
            locked = not vim.bo.modifiable
            cb(nil, "no key")
        end
        local _, restore_notify = helpers.capture_notify()
        run_on_freewrite()
        restore_notify()
        assert.truthy(locked)
        assert.truthy(vim.bo.modifiable)

        replies({ vim.json.encode({ chunks = { { paragraphs = { 2 }, target = id_of("After: The Port › The strike") } } }) })
        local _, restore = helpers.scripted_ui({ nil })
        run_on_freewrite()
        restore()
        assert.truthy(vim.bo.modifiable)
    end)

    it("keeps a paragraph in the freewrite when its home cannot be written", function()
        replies({ vim.json.encode({ chunks = { { paragraphs = { 2 }, target = id_of("After: The Port › The strike") } } }) })
        local write_file = project.write_file
        project.write_file = function(p, s)
            if p:match("text%.wyt%.md$") then return false end
            return write_file(p, s)
        end
        local messages, restore_notify = helpers.capture_notify()
        local _, restore = helpers.scripted_ui({ t("place_leave"), t("place_it") })
        run_on_freewrite()
        restore()
        restore_notify()
        project.write_file = write_file

        assert.equals(FREEWRITE, helpers.read(root .. "freewrite/2026-01-01-0900.md"))
        assert.equals(t("place_nothing"), messages[#messages].msg)
    end)

    it("adds a new idea to a group, in the plan and as the group's last prose", function()
        replies({ vim.json.encode({ chunks = {
            { paragraphs = { 2 }, target = id_of("New idea in: The Port › The strike"), idea = "## the chained gate" },
        } }) })
        local _, restore = helpers.scripted_ui({ t("place_leave"), t("place_it") })
        run_on_freewrite()
        restore()

        -- The model's "## " is stripped: a name lands in a plan line.
        local plan = helpers.read(root .. "plan.wyt.md")
        assert.truthy(plan:find("- the chained gate [Group: The strike]", 1, true))
        assert.truthy(plan:find("## Group: The strike [Implemented]\n- the union hall\n- the chained gate", 1, true))
        assert.matches("Nobody unloaded anything that week%.\n\nThe gate was chained%.\nA man in a grey coat watched it%.\n",
            helpers.read(root .. "text.wyt.md"))
    end)

    it("opens a new group in the text and claims it in the plan", function()
        replies({ vim.json.encode({ chunks = {
            { paragraphs = { 2 }, target = id_of("New group in: The Port"), group = "The gate", idea = "the chained gate" },
        } }) })
        local _, restore = helpers.scripted_ui({ t("place_leave"), t("place_it") })
        run_on_freewrite()
        restore()

        assert.matches("Nobody unloaded anything that week%.\n\n## Group: The gate\n\nThe gate was chained%.\nA man",
            helpers.read(root .. "text.wyt.md"))
        local plan = helpers.read(root .. "plan.wyt.md")
        assert.truthy(plan:find("- the chained gate [Group: The gate]", 1, true))
        assert.truthy(vim.endswith(plan, "\n\n## Group: The gate [Implemented]\n- the chained gate\n"))
        -- And it is a home from now on.
        assert.truthy(id_of("After: The Port › The gate"))
    end)

    it("makes a new group a section of its own where sections nest", function()
        helpers.write(root .. "config.wyt.yml", "lang: en\ntype: essay\ncontent_type: content\nsections: true\nname: The Port\n")
        replies({ vim.json.encode({ chunks = {
            { paragraphs = { 2 }, target = id_of("New group in: The Port"), group = "The Gate", idea = "the chained gate" },
        } }) })
        local _, restore = helpers.scripted_ui({ t("place_leave"), t("place_it") })
        run_on_freewrite()
        restore()

        assert.matches("sections: false", helpers.read(root .. "the-gate/config.wyt.yml"))
        assert.equals("## Group: the chained gate\n\nThe gate was chained.\nA man in a grey coat watched it.\n",
            helpers.read(root .. "the-gate/text.wyt.md"))
        assert.truthy(helpers.read(root .. "plan.wyt.md"):find("## Group: The Gate [Implemented]", 1, true))
        -- The walk the export and :WYTNav make finds it.
        assert.truthy(id_of("After: The Gate › the chained gate"))
    end)

    it("refuses a new group whose name is taken, and keeps the paragraph", function()
        replies({ vim.json.encode({ chunks = {
            { paragraphs = { 2 }, target = id_of("New group in: The Port"), group = "The strike", idea = "the gate" },
        } }) })
        local messages, restore_notify = helpers.capture_notify()
        local _, restore = helpers.scripted_ui({ t("place_leave"), t("place_it") })
        run_on_freewrite()
        restore()
        restore_notify()

        local said = vim.tbl_map(function(m) return m.msg end, messages)
        assert.truthy(vim.tbl_contains(said, t("place_taken")))
        assert.equals(FREEWRITE, helpers.read(root .. "freewrite/2026-01-01-0900.md"))
    end)

    it("redoes the proposal with the writer's note, then asks again", function()
        local after = id_of("After: The Port › The strike")
        local prompts = replies({
            vim.json.encode({ chunks = { { paragraphs = { 1, 2, 3 }, target = "keep" } } }),
            vim.json.encode({ chunks = { { paragraphs = { 2 }, target = after }, { paragraphs = { 1, 3 }, target = "keep" } } }),
        })
        local log, restore = helpers.scripted_ui({
            t("place_change"), "", -- an empty note goes back to the same menu
            t("place_change"), "the gate is the strike",
            -- Walked top to bottom: the kept 1 and 3 come before 2.
            t("place_leave"), t("place_it"),
        })
        run_on_freewrite()
        restore()

        assert.equals(2, #prompts)
        assert.matches('did not want "nowhere yet: it stays in freewrite" and says: the gate is the strike', prompts[2])
        assert.truthy(prompts[2]:find("[3] Maybe the dog", 1, true))
        assert.same({ t("place_leave"), t("place_change") }, log[3].items)
        assert.matches("Nobody unloaded anything that week%.\n\nThe gate was chained%.", helpers.read(root .. "text.wyt.md"))
    end)

    it("stops on Esc and keeps what was placed so far", function()
        replies({ vim.json.encode({ chunks = {
            { paragraphs = { 1 }, target = id_of("After: The Port › The strike") },
            { paragraphs = { 2 }, target = id_of("After: The Port › The strike") },
        } }) })
        local _, restore = helpers.scripted_ui({ t("place_it"), nil })
        run_on_freewrite()
        restore()

        local text = helpers.read(root .. "text.wyt.md")
        assert.truthy(text:find("The harbour master had the only key.", 1, true))
        assert.falsy(text:find("The gate was chained.", 1, true))
        assert.truthy(helpers.read(root .. "freewrite/2026-01-01-0900.md"):find("The gate was chained.", 1, true))
    end)

    it("saves this project's buffers first, and nobody else's", function()
        local outside = vim.fn.tempname() .. ".md"
        helpers.write(outside, "theirs\n")
        vim.cmd("edit " .. vim.fn.fnameescape(outside))
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "unsaved" })
        local other = vim.api.nvim_get_current_buf()
        vim.cmd("edit " .. vim.fn.fnameescape(root .. "text.wyt.md"))
        vim.api.nvim_buf_set_lines(0, -1, -1, false, { "typed before Place" })
        llm.generate_text = function(_, cb) cb(nil, "no key") end
        local _, restore = helpers.capture_notify()
        run_on_freewrite()
        restore()

        assert.truthy(helpers.read(root .. "text.wyt.md"):find("typed before Place", 1, true))
        assert.equals("theirs\n", helpers.read(outside))
        vim.api.nvim_buf_delete(other, { force = true })
        os.remove(outside)
    end)

    it("says so when the model proposes no usable place", function()
        replies({ vim.json.encode({ chunks = { { paragraphs = { 1 }, target = "T99" } } }) })
        local messages, restore = helpers.capture_notify()
        run_on_freewrite()
        restore()
        assert.equals(t("place_no_reply"), messages[#messages].msg)
        assert.equals(FREEWRITE, helpers.read(root .. "freewrite/2026-01-01-0900.md"))
    end)

    it("stops on Esc at the change note, like Esc on the menu", function()
        local prompts = replies({ vim.json.encode({ chunks = { { paragraphs = { 2 }, target = id_of("After: The Port › The strike") } } }) })
        local messages, restore_notify = helpers.capture_notify()
        local _, restore = helpers.scripted_ui({ t("place_leave"), t("place_change"), nil })
        run_on_freewrite()
        restore()
        restore_notify()

        assert.equals(1, #prompts)
        assert.equals(t("place_nothing"), messages[#messages].msg)
        assert.equals(FREEWRITE, helpers.read(root .. "freewrite/2026-01-01-0900.md"))
        assert.truthy(vim.bo.modifiable)
    end)

    it("says a placeholder filled meanwhile is gone, and writes nothing", function()
        local target
        for _, x in ipairs(place.targets(project)) do
            if x.kind == "placeholder" then target = x end
        end
        helpers.write(root .. "text.wyt.md", (TEXT:gsub("%*Create[^\n]*", "Already written.")))
        local files, why = place.apply(project, { target = target }, "New text.")
        assert.is_nil(files)
        assert.equals("place_gone", why)
        assert.falsy(helpers.read(root .. "text.wyt.md"):find("New text.", 1, true))
    end)

    it("says so when the freewrite holds only its prompt", function()
        helpers.write(root .. "freewrite/2026-01-01-0900.md", "> Who opens the gate?\n")
        local called = false
        llm.generate_text = function() called = true end
        local messages, restore = helpers.capture_notify()
        run_on_freewrite()
        restore()
        assert.falsy(called)
        assert.equals(t("place_empty"), messages[#messages].msg)
    end)

    it("picks among the freewrites, newest first, when none is on screen", function()
        helpers.write(root .. "freewrite/2026-02-01-0900.md", "Later words.\n")
        vim.cmd("edit " .. vim.fn.fnameescape(root .. "text.wyt.md"))
        local prompts = replies({ vim.json.encode({ chunks = { { paragraphs = { 1 }, target = "keep" } } }) })
        local log, restore = helpers.scripted_ui({ "2026-02-01-0900.md", nil })
        place.open()
        restore()

        assert.same({ "2026-02-01-0900.md", "2026-01-01-0900.md" }, log[1].items)
        assert.truthy(prompts[1]:find("[1] Later words.", 1, true))
    end)

    it("says there is nothing to place when the project has no freewrite", function()
        vim.fn.delete(root .. "freewrite", "rf")
        vim.cmd("edit " .. vim.fn.fnameescape(root .. "text.wyt.md"))
        local messages, restore = helpers.capture_notify()
        place.open()
        restore()
        assert.equals(t("place_none"), messages[#messages].msg)
    end)

    it("leaves the freewrite alone when the model cannot be reached", function()
        llm.generate_text = function(_, cb) cb(nil, "no key") end
        local messages, restore = helpers.capture_notify()
        run_on_freewrite()
        restore()

        assert.equals(FREEWRITE, helpers.read(root .. "freewrite/2026-01-01-0900.md"))
        assert.matches("no key", messages[#messages].msg)
    end)
end)
