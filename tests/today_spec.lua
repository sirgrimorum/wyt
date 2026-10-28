-- :WYTToday reads where the last session stopped from git, and what is still
-- open from the plans. These build a real repository with commits dated in the
-- past, since the depth of the recap is decided by how old the last one is.
local helpers = require("tests.helpers")
local project = require("wyt.project")
local status = require("wyt.status")
local today = require("wyt.today")

local DAY = 24 * 3600

-- The fixture machine may have no git identity, and the commit date is the
-- whole point, so both are set per call rather than taken from the environment.
local function git(root, args, when)
    local cmd = { "git", "-C", root, "-c", "user.name=t", "-c", "user.email=t@t" }
    vim.list_extend(cmd, args)
    local env = when and { GIT_AUTHOR_DATE = when .. " +0000", GIT_COMMITTER_DATE = when .. " +0000" } or nil
    local r = vim.system(cmd, { text = true, env = env }):wait()
    assert(r.code == 0, table.concat(args, " ") .. ": " .. (r.stderr or ""))
end

-- "Save: " like the commits a writer's save makes, the only ones last_edit reads.
local function commit_all(root, seconds_ago, msg)
    git(root, { "add", "." })
    git(root, { "commit", "-q", "-m", msg or "Save: fixture" }, "@" .. tostring(os.time() - seconds_ago))
end

local TEXT = table.concat({
    "## Group: The arrival",
    "",
    "She came on the night ferry.",
    "The port was closed.",
    "",
    "*Create a paragraph about: [the harbour master]*",
    "",
    "## Group: The strike",
    "",
    "Nobody unloaded anything that week.",
    "",
    "*Create a paragraph about: [the union hall]*",
}, "\n")

describe("today.recap_depth", function()
    it("gives the paragraph alone under a day", function()
        assert.equals("paragraph", today.recap_depth(0))
        assert.equals("paragraph", today.recap_depth(DAY - 1))
    end)

    it("adds the scene up to a week, the chapter past it", function()
        assert.equals("scene", today.recap_depth(DAY))
        assert.equals("scene", today.recap_depth(7 * DAY - 1))
        assert.equals("chapter", today.recap_depth(7 * DAY))
    end)
end)

describe("today.ago", function()
    it("says how long, in the project's language", function()
        local en = function(k) return require("wyt.localization").t(k, "en") end
        local es = function(k) return require("wyt.localization").t(k, "es") end
        assert.equals("1 min ago", today.ago(20, en))
        assert.equals("2 h ago", today.ago(2 * 3600, en))
        assert.equals("yesterday", today.ago(DAY + 60, en))
        assert.equals("9 days ago", today.ago(9 * DAY, en))
        assert.equals("hace 9 días", today.ago(9 * DAY, es))
    end)
end)

describe("status of a plan", function()
    local root
    before_each(function() helpers.cleanup(root); root = helpers.project() end)

    it("counts the ideas no group claimed and the groups not implemented", function()
        local gaps = status.plan_gaps(project, table.concat({
            "# P", "", "## Ideas", "", "- a [Group: G]", "- b", "- c", "",
            "## Group: G [Implemented]", "- a", "",
            "## Group: H", "",
            "## Group: K [Edited]", "",
        }, "\n"))
        assert.equals(2, gaps.ungrouped)
        assert.same({ "H", "K" }, gaps.pending_groups)
    end)
end)

describe("status of a text", function()
    local root
    before_each(function() helpers.cleanup(root); root = helpers.project() end)

    local lines = vim.split(TEXT, "\n", { plain = true })

    it("finds the paragraph a session ended in, even from the blank line after it", function()
        local text, last = status.paragraph_at(project, lines, 5)
        assert.equals("She came on the night ferry.\nThe port was closed.", text)
        assert.equals(4, last)
    end)

    it("skips a placeholder back to the prose before it", function()
        assert.equals("Nobody unloaded anything that week.", (status.paragraph_at(project, lines, 12)))
    end)

    it("reads the scene the line is in, without markers or placeholders", function()
        local scene, name = status.scene_at(project, lines, 10)
        assert.equals("The strike", name)
        assert.equals("Nobody unloaded anything that week.", scene)
    end)
end)

describe("status.last_edit", function()
    local root
    before_each(function() helpers.cleanup(root); root = helpers.project() end)

    it("is nil before any text was committed", function()
        git(root, { "init", "-q" })
        commit_all(root, 0)
        assert.is_nil(status.last_edit(root))
    end)

    it("points at the last line the newest text commit changed, and its time", function()
        git(root, { "init", "-q" })
        helpers.write(root .. "text.wyt.md", TEXT)
        commit_all(root, 5 * DAY)
        helpers.write(root .. "text.wyt.md", (TEXT:gsub("The port was closed%.", "The port was closed. It rained.")))
        commit_all(root, 3 * DAY)
        -- A later plan save is not where the writing stopped.
        helpers.write(root .. "plan.wyt.md", helpers.read(root .. "plan.wyt.md") .. "\n- later idea\n")
        commit_all(root, 0)

        local edit = status.last_edit(root)
        assert.matches("text%.wyt%.md$", edit.path)
        assert.equals(4, edit.line)
        assert.truthy(math.abs(os.time() - 3 * DAY - edit.time) < 60)
    end)

    it("ignores a commit WYT made that carried text, like implementing a group", function()
        git(root, { "init", "-q" })
        helpers.write(root .. "text.wyt.md", TEXT)
        commit_all(root, 3 * DAY)
        helpers.write(root .. "text.wyt.md", TEXT .. "\n\n*Create a paragraph about: [new idea]*\n")
        commit_all(root, 0, "Implement group: New")

        assert.truthy(math.abs(os.time() - 3 * DAY - status.last_edit(root).time) < 60)
    end)

    it("finds the text of a project kept inside a larger repository", function()
        local outer = vim.fn.fnamemodify(root, ":h:h")
        git(outer, { "init", "-q" })
        helpers.write(root .. "text.wyt.md", TEXT)
        commit_all(outer, 0)

        assert.equals(root .. "text.wyt.md", status.last_edit(root).path)
    end)
end)

describe("today.options", function()
    local t = function(k) return require("wyt.localization").t(k, "en") end

    it("continues first, then the placeholders ahead of the last edit, then free writing", function()
        local sections = {
            { dir = "/p/", placeholders = { { line = 2, idea = "behind" }, { line = 9, idea = "ahead" } }, pending_groups = {}, ungrouped = 0 },
            { dir = "/p/ref/", definition = true, placeholders = { { line = 1, idea = "a character" } }, pending_groups = {}, ungrouped = 0 },
        }
        local edit = { path = "/p/text.wyt.md", line = 5, line_end = 5 }
        local items = today.options(edit, "Ch › Scene", sections, "a prompt", t)
        assert.equals("Continue: Ch › Scene", items[1].label)
        assert.equals("Write: ahead", items[2].label)
        assert.equals("Write: behind", items[3].label)
        assert.equals("Freewrite on the prompt", items[4].label)
        assert.equals(4, #items)
    end)

    it("offers two placeholders at most", function()
        local phs = { { line = 1, idea = "a" }, { line = 2, idea = "b" }, { line = 3, idea = "c" } }
        local items = today.options(nil, nil, { { dir = "/p/", placeholders = phs, pending_groups = {}, ungrouped = 0 } }, nil, t)
        assert.same({ "Write: a", "Write: b", "Freewrite" }, vim.tbl_map(function(i) return i.label end, items))
    end)
end)

describe("today.open_summary", function()
    local t = function(k) return require("wyt.localization").t(k, "en") end

    it("counts what is open in the content sections, and the markers of every section", function()
        local sections = {
            { placeholders = { {}, {} }, markers = { {} }, pending_groups = { "G" }, ungrouped = 3 },
            { definition = true, placeholders = { {} }, markers = { {}, {} }, pending_groups = { "H" }, ungrouped = 5 },
        }
        assert.equals("paragraphs to write: 2, groups to implement: 1, ideas without a group: 3, wyt markers to answer: 3",
            today.open_summary(sections, t))
        assert.is_nil(today.open_summary({ { placeholders = {}, markers = {}, pending_groups = {}, ungrouped = 0 } }, t))
    end)
end)

describe("freewrite.open", function()
    local root
    before_each(function() helpers.cleanup(root); root = helpers.project() end)

    it("knows a section named Freewrite from free writing", function()
        local freewrite = require("wyt.freewrite")
        assert.truthy(freewrite.is_freewrite(root .. "freewrite/2026-01-01-0900.md"))
        assert.falsy(freewrite.is_freewrite(root .. "freewrite/plan.wyt.md"))
        assert.falsy(freewrite.is_freewrite(root .. "freewrite/text.wyt.md"))
    end)

    it("strips the screen and commits on save, through the real autocmds", function()
        git(root, { "init", "-q" })
        commit_all(root, 0)
        require("wyt.autocmd").setup()
        local number = vim.o.number
        vim.o.number = true
        require("wyt.freewrite").open("Who opens the gate?")
        vim.cmd("stopinsert")
        local bare = { vim.wo.number, vim.wo.signcolumn, vim.wo.wrap, vim.wo.linebreak }
        vim.cmd("write")
        vim.o.number = number
        vim.api.nvim_del_augroup_by_name("WYT_Plugin")

        assert.same({ false, "no", true, true }, bare)
        local r = vim.system({ "git", "-C", root, "log", "-1", "--format=%s" }, { text = true }):wait()
        assert.matches("^Save: freewrite/", r.stdout)
    end)

    it("starts a new paragraph when it reopens a file written this minute", function()
        local freewrite = require("wyt.freewrite")
        -- Pinned, or a minute ticking over between the two opens makes two files.
        local date = os.date
        os.date = function() return "2026-01-01-0900" end
        freewrite.open("Who opens the gate?")
        vim.cmd("stopinsert")
        vim.api.nvim_buf_set_lines(0, 2, 3, false, { "The gate was chained." })
        vim.cmd("write")
        freewrite.open("Who opens the gate?")
        os.date = date
        vim.cmd("stopinsert")
        assert.same({ "> Who opens the gate?", "", "The gate was chained.", "", "" },
            vim.api.nvim_buf_get_lines(0, 0, -1, false))
        assert.equals(5, vim.api.nvim_win_get_cursor(0)[1])
    end)

    it("leaves no file behind for a start abandoned without a word", function()
        require("wyt.autocmd").setup()
        local freewrite = require("wyt.freewrite")
        -- Two minutes, or both opens land on the same file.
        local date = os.date
        os.date = function() return "2026-01-01-0900" end
        freewrite.open("Who opens the gate?")
        vim.cmd("stopinsert")
        local empty = vim.api.nvim_buf_get_name(0)
        vim.cmd("bwipeout!")
        os.date = function() return "2026-01-01-0901" end
        freewrite.open(nil)
        os.date = date
        vim.cmd("stopinsert")
        local written = vim.api.nvim_buf_get_name(0)
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "The gate was chained." })
        vim.cmd("write")
        vim.cmd("bwipeout!")
        vim.api.nvim_del_augroup_by_name("WYT_Plugin")

        assert.is_nil((vim.uv or vim.loop).fs_stat(empty))
        assert.truthy((vim.uv or vim.loop).fs_stat(written))
    end)
end)

describe(":WYTToday end to end", function()
    local root
    before_each(function() helpers.cleanup(root) end)

    local function port(seconds_ago)
        -- Flat: the text sits at the root, which a project of sub-sections never exports.
        root = helpers.project({ sections = false, name = "The Port", description = "A town during a dock strike." })
        git(root, { "init", "-q" })
        helpers.write(root .. "text.wyt.md", TEXT)
        commit_all(root, seconds_ago)
    end

    it("recaps the scene of a session three days old and freewrites on its prompt", function()
        port(3 * DAY)
        -- A heading the model invents never reaches the file it heads.
        local captured = helpers.capture_prompt('{"summary": "She arrives; the port is shut.", "prompt": "## Who opens the gate?"}')
        local log = helpers.scripted_ui({ "Freewrite on the prompt" })
        helpers.capture_notify()
        today.open()
        vim.cmd("stopinsert")

        assert.matches("A town during a dock strike", captured.prompt)
        -- The whole file was the last commit, so the session ended in the last
        -- scene: that one is sent, the scene before it is not.
        assert.matches("Nobody unloaded anything that week", captured.prompt)
        assert.has_no_match("night ferry", captured.prompt)
        -- The fixture writes CRLF on Windows: no `\r` may reach a label.
        assert.equals("Continue: The Port › The strike", log[1].items[1])
        -- Neither placeholder lies past the last edit, so plan order decides.
        assert.equals("Write: the harbour master", log[1].items[2])
        assert.equals("Write: the union hall", log[1].items[3])
        -- readdir, not glob: glob finds nothing under an 8.3 temp path (ANDRES~1).
        local files = vim.fn.readdir(root .. "freewrite")
        assert.equals(1, #files)
        -- The writer types on the line after a blank one, never on the blank
        -- line itself: a driven session once glued the text to the prompt.
        assert.same({ "> Who opens the gate?", "", "" }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
        assert.equals(3, vim.api.nvim_win_get_cursor(0)[1])
    end)

    it("offers two placeholders with the same idea once", function()
        port(3 * DAY)
        helpers.write(root .. "text.wyt.md", (TEXT:gsub("the harbour master", "the union hall")))
        commit_all(root, 3 * DAY)
        helpers.capture_prompt('{"summary": "s", "prompt": "p"}')
        local log = helpers.scripted_ui({})
        helpers.capture_notify()
        today.open()
        -- The second commit changed only the arrival, so Continue points there.
        assert.same({ "Write: the union hall", "Freewrite on the prompt" }, { log[1].items[2], log[1].items[3] })
        assert.equals(3, #log[1].items)
    end)

    it("sends the whole file after a week away", function()
        port(8 * DAY)
        local captured = helpers.capture_prompt('{"summary": "s", "prompt": "p"}')
        helpers.scripted_ui({})
        helpers.capture_notify()
        today.open()
        assert.matches("night ferry", captured.prompt)
        assert.matches("Nobody unloaded anything that week", captured.prompt)
    end)

    it("still opens the brief from disk when the model cannot be reached", function()
        port(3 * DAY)
        require("wyt.llm").generate_text = function(_, cb) cb(nil, "no key") end
        local log = helpers.scripted_ui({})
        local messages = helpers.capture_notify()
        today.open()
        assert.equals("Continue: The Port › The strike", log[1].items[1])
        assert.equals("Freewrite", log[1].items[#log[1].items])
        assert.truthy(vim.iter(messages):any(function(m) return m.msg:find("no key", 1, true) end))
    end)
end)
