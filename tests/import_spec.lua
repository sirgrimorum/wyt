-- :WYTImport brings the Boox folder in as freewrite. The model is stubbed; what
-- is checked is what it is sent (the recognized text, or the PDF and the page
-- to start from), what lands in freewrite for each menu choice, that the
-- manifest brings only what is new the next time, and that the Boox folder is
-- never written to.
local helpers = require("tests.helpers")
local project = require("wyt.project")
local import = require("wyt.import")
local llm = require("wyt.llm")
local uv = vim.uv or vim.loop
-- Put back before each spec: the runner has no after_each.
local generate_text = llm.generate_text

local function t(k) return require("wyt.localization").t(k, "en") end

local function setup(boox)
    local root = helpers.project({ sections = false, name = "Notes" })
    if boox then
        local config = project.read_file(root .. "config.wyt.yml")
        project.write_file(root .. "config.wyt.yml", config .. "import_dir: '" .. boox .. "'\n")
    end
    vim.system({ "git", "-C", root, "init", "-q" }):wait()
    return root
end

-- A Boox folder outside the project, the way Dropbox keeps it.
local function boox_dir()
    local dir = (vim.fn.tempname() .. "/boox/"):gsub("\\", "/")
    vim.fn.mkdir(dir, "p")
    return dir
end

-- The model's replies, one per call, and what each call was sent.
local function replies(list)
    local calls = {}
    llm.generate_text = function(prompt, cb, opts)
        calls[#calls + 1] = { prompt = prompt, opts = opts or {} }
        cb(table.remove(list, 1))
    end
    return calls
end

local function run(answers)
    local log, restore = helpers.scripted_ui(answers)
    local messages, restore_notify = helpers.capture_notify()
    import.open()
    restore_notify()
    restore()
    return log, messages
end

local function freewrites(root)
    local dir = root .. "freewrite/"
    local out = {}
    for _, name in ipairs(vim.fn.isdirectory(dir) == 1 and vim.fn.readdir(dir) or {}) do
        out[#out + 1] = project.read_file(dir .. name)
    end
    return out
end

local function last_commit(root)
    return vim.system({ "git", "-C", root, "log", "-1", "--format=%s" }, { text = true }):wait().stdout
end

describe("import.word_diff", function()
    it("marks only the words that changed, and keeps the paragraphs", function()
        local marked, n = import.word_diff("teh cat sat\n\non a mat", "the cat sat\n\non the mat")
        assert.equals("[-teh-]{+the+} cat sat\n\non [-a-]{+the+} mat", marked)
        assert.equals(2, n)
    end)

    it("shows a word dropped and a word added", function()
        assert.equals("the [-big-] cat", (import.word_diff("the big cat", "the cat")))
        assert.equals("the {+big+} cat", (import.word_diff("the cat", "the big cat")))
        assert.equals("one two {+three+}", (import.word_diff("one two", "one two three")))
    end)

    it("counts no change when there is none", function()
        assert.equals(0, select(2, import.word_diff("same words", "same  words")))
    end)
end)

describe("import.pending", function()
    local root, boox
    before_each(function()
        helpers.cleanup(root)
        boox = boox_dir()
        root = setup(boox)
    end)

    it("reads a .txt without its BOM or CRLF, and leaves other files alone", function()
        project.write_file(boox .. "Notes.txt", "\239\187\191first line\r\nsecond line\r\n")
        project.write_file(boox .. "cover.png", "png")
        local items = import.pending(project, boox, {})
        assert.equals(1, #items)
        assert.equals("first line\nsecond line", items[1].text)
    end)

    it("brings only the tail of a .txt that grew, and all of one that was rewritten", function()
        local first = "page one\n"
        project.write_file(boox .. "Notes.txt", first .. "page two\n")
        local manifest = { ["Notes.txt"] = { bytes = #first, sha = vim.fn.sha256(first) } }
        assert.equals("page two", import.pending(project, boox, manifest)[1].text)

        project.write_file(boox .. "Notes.txt", "a new start\n")
        assert.equals("a new start", import.pending(project, boox, manifest)[1].text)

        project.write_file(boox .. "Notes.txt", first)
        assert.same({}, import.pending(project, boox, manifest))
    end)

    it("reads a .pdf from the page after the last one imported, and skips one unchanged", function()
        project.write_file(boox .. "Notebook.pdf", "%PDF-1.4 fake")
        local stat = uv.fs_stat(boox .. "Notebook.pdf")
        assert.equals(4, import.pending(project, boox, { ["Notebook.pdf"] = { size = 1, mtime = 1, pages = 3 } })[1].from)
        assert.same({}, import.pending(project, boox,
            { ["Notebook.pdf"] = { size = stat.size, mtime = stat.mtime.sec, pages = 3 } }))
    end)

    it("lists the oldest first", function()
        project.write_file(boox .. "b.txt", "newer\n")
        project.write_file(boox .. "a.txt", "older\n")
        uv.fs_utime(boox .. "a.txt", 1000, 1000)
        assert.same({ "a.txt", "b.txt" }, vim.tbl_map(function(i) return i.name end, import.pending(project, boox, {})))
    end)

    it("reads only files, not a folder with a matching name", function()
        vim.fn.mkdir(boox .. "folder.txt", "p")
        project.write_file(boox .. "real.txt", "words\n")
        assert.same({ "real.txt" }, vim.tbl_map(function(i) return i.name end, import.pending(project, boox, {})))
    end)
end)

describe(":WYTImport", function()
    local root, boox
    before_each(function()
        llm.generate_text = generate_text
        helpers.cleanup(root)
        boox = boox_dir()
        root = setup(boox)
    end)

    it("asks for the folder the first time, and keeps it in the config", function()
        helpers.cleanup(root)
        root = setup(nil)
        project.write_file(boox .. "Notes.txt", "hello\n")
        replies({ "hello" })
        local log = run({ boox, t("import_keep"), t("import_place_later") })
        assert.equals("input", log[1].kind)
        assert.equals(boox, project.config_dir("import_dir"))
        assert.matches("import_dir: '" .. vim.pesc(boox) .. "'", project.read_file(root .. "config.wyt.yml"))
        assert.equals(1, #freewrites(root))
    end)

    it("says so when the folder is not there, and asks nothing", function()
        helpers.cleanup(root)
        root = setup(boox .. "gone/")
        local log, messages = run({})
        assert.equals(0, #log)
        assert.matches("No such folder", messages[1].msg)
    end)

    it("writes the cleanup as a freewrite, records it, and never touches the Boox file", function()
        local source = "Teh ferry came in\r\nat night.\r\n"
        project.write_file(boox .. "Ferry notes.txt", source)
        local before = uv.fs_stat(boox .. "Ferry notes.txt").mtime.sec
        local calls = replies({ "The ferry came in at night." })
        local log, messages = run({ t("import_use"), t("import_place_later") })

        assert.matches("<text>\nTeh ferry came in\nat night.\n</text>", calls[1].prompt)
        -- The diff, not the bare cleanup, is what the writer is shown.
        assert.same({ t("import_use"), t("import_change"), t("import_keep"), t("import_skip") }, log[1].items)
        assert.same({ "> Boox: Ferry notes.txt\n\nThe ferry came in at night.\n" }, freewrites(root))
        local name = vim.fn.readdir(root .. "freewrite/")[1]
        assert.matches("^%d%d%d%d%-%d%d%-%d%d%-%d%d%d%d%-ferry%-notes%.md$", name)
        assert.equals(#"Teh ferry came in\nat night.\n", import.read_manifest(project)["Ferry notes.txt"].bytes)
        assert.matches("^Save: imported from the Boox", last_commit(root))
        assert.equals(source, project.read_file(boox .. "Ferry notes.txt"))
        assert.equals(before, uv.fs_stat(boox .. "Ferry notes.txt").mtime.sec)
        assert.same({ "Ferry notes.txt" }, vim.fn.readdir(boox))
        assert.matches("Imported 1", messages[#messages].msg)
    end)

    it("keeps the recognition as it was when asked to", function()
        project.write_file(boox .. "n.txt", "Teh ferry\n")
        replies({ "The ferry" })
        run({ t("import_keep"), t("import_place_later") })
        assert.same({ "> Boox: n.txt\n\nTeh ferry\n" }, freewrites(root))
    end)

    it("asks again with the writer's note on Change it…", function()
        project.write_file(boox .. "n.txt", "Ines came\n")
        local calls = replies({ "Inés came", "Ines came" })
        run({ t("import_change"), "Ines is spelled without the accent", t("import_use"), t("import_place_later") })
        assert.equals(2, #calls)
        assert.matches("<previous>\nInés came\n</previous>\nand says: Ines is spelled without the accent", calls[2].prompt)
        assert.same({ "> Boox: n.txt\n\nInes came\n" }, freewrites(root))
    end)

    it("goes back to the menu on an empty note, and stops on Esc", function()
        project.write_file(boox .. "n.txt", "Teh line\n")
        local calls = replies({ "The line" })
        local log = run({ t("import_change"), "", t("import_change"), nil })
        assert.equals(1, #calls)
        assert.equals("select", log[3].kind)
        assert.equals(4, #log)
        assert.equals(0, #freewrites(root))
    end)

    it("reads a .txt whole again when an edit kept its length", function()
        project.write_file(boox .. "n.txt", "cat\n")
        replies({ "cat" })
        run({ t("import_keep"), t("import_place_later") })
        project.write_file(boox .. "n.txt", "bat\n")
        local calls = replies({ "bat" })
        run({ t("import_keep"), t("import_place_later") })
        assert.matches("<text>\nbat\n</text>", calls[1].prompt)
    end)

    it("leaves a skipped file to the next import, and brings only what is new after", function()
        project.write_file(boox .. "n.txt", "first\n")
        replies({ "first" })
        local _, messages = run({ t("import_skip") })
        assert.equals(0, #freewrites(root))
        assert.same({}, import.read_manifest(project))
        assert.matches("Nothing imported", messages[#messages].msg)
        assert.has_no_match("imported from the Boox", last_commit(root))

        replies({ "first" })
        run({ t("import_keep"), t("import_place_later") })
        project.write_file(boox .. "n.txt", "first\nsecond\n")
        local calls = replies({ "second" })
        run({ t("import_keep"), t("import_place_later") })
        assert.has_no_match("first", calls[1].prompt)
        assert.equals(2, #freewrites(root))
    end)

    it("stops on <Esc> and keeps what was already taken", function()
        project.write_file(boox .. "a.txt", "older\n")
        project.write_file(boox .. "b.txt", "newer\n")
        uv.fs_utime(boox .. "a.txt", 1000, 1000)
        replies({ "older", "newer" })
        run({ t("import_keep"), nil, t("import_place_later") })
        assert.same({ "> Boox: a.txt\n\nolder\n" }, freewrites(root))
        assert.is_nil(import.read_manifest(project)["b.txt"])
    end)

    it("offers the recognition as it is when the model fails", function()
        project.write_file(boox .. "n.txt", "as written\n")
        llm.generate_text = function(_, cb) cb(nil, "no key") end
        local log = run({ t("import_keep"), t("import_place_later") })
        assert.same({ t("import_keep"), t("import_skip") }, log[1].items)
        assert.equals(1, #freewrites(root))
    end)

    it("sends a .pdf with the page to start from, and records how many it has", function()
        project.write_file(boox .. "Notebook.pdf", "%PDF-1.4 fake")
        local stat = uv.fs_stat(boox .. "Notebook.pdf")
        project.write_file(root .. "imports.wyt.json", vim.json.encode({ ["Notebook.pdf"] = { size = 1, mtime = 1, pages = 2 } }))
        local calls = replies({ vim.json.encode({ pages = 5, text = "Page three, in ink." }) })
        run({ t("import_it"), t("import_place_later") })

        assert.equals(vim.base64.encode("%PDF-1.4 fake"), calls[1].opts.pdf)
        assert.matches("from page 3 to the end", calls[1].prompt)
        assert.same({ "> Boox: Notebook.pdf\n\nPage three, in ink.\n" }, freewrites(root))
        assert.same({ size = stat.size, mtime = stat.mtime.sec, pages = 5 }, import.read_manifest(project)["Notebook.pdf"])
    end)

    it("records a .pdf with no new pages without a freewrite or a question", function()
        project.write_file(boox .. "Notebook.pdf", "%PDF-1.4 fake")
        replies({ vim.json.encode({ pages = 2, text = "" }) })
        local log = run({})
        assert.equals(0, #log)
        assert.equals(0, #freewrites(root))
        assert.equals(2, import.read_manifest(project)["Notebook.pdf"].pages)
        -- Only the manifest changed, and it is committed all the same.
        assert.matches("^Save: imported from the Boox", last_commit(root))
    end)

    it("never lowers the page count it recorded", function()
        project.write_file(boox .. "Notebook.pdf", "%PDF-1.4 fake")
        project.write_file(root .. "imports.wyt.json", vim.json.encode({ ["Notebook.pdf"] = { size = 1, mtime = 1, pages = 6 } }))
        replies({ vim.json.encode({ pages = 2, text = "" }) })
        run({})
        assert.equals(6, import.read_manifest(project)["Notebook.pdf"].pages)
    end)

    it("asks again for a .pdf with the note and the last transcription, or skips it", function()
        project.write_file(boox .. "Notebook.pdf", "%PDF-1.4 fake")
        local calls = replies({ vim.json.encode({ pages = 1, text = "Ines came." }),
            vim.json.encode({ pages = 1, text = "Inés came." }) })
        run({ t("import_change"), "the accent on Inés", t("import_skip") })
        assert.equals(2, #calls)
        assert.equals(calls[1].opts.pdf, calls[2].opts.pdf)
        assert.matches("<previous>\nInes came.\n</previous>\nand says: the accent on Inés", calls[2].prompt)
        assert.equals(0, #freewrites(root))
        assert.is_nil(import.read_manifest(project)["Notebook.pdf"])
    end)

    it("leaves a .pdf the model could not read to the next import", function()
        project.write_file(boox .. "Notebook.pdf", "%PDF-1.4 fake")
        llm.generate_text = function(_, cb) cb(nil, "no key") end
        local log, messages = run({})
        assert.equals(0, #log)
        assert.truthy(vim.iter(messages):any(function(m) return m.msg:find("no key", 1, true) ~= nil end))
        assert.same({}, import.read_manifest(project))
    end)

    it("skips a file too big to send, and asks the model nothing", function()
        local calls = replies({})
        local log, restore = helpers.scripted_ui({})
        local messages, restore_notify = helpers.capture_notify()
        import.run({ { name = "Big.pdf", kind = "pdf", path = boox .. "Big.pdf", from = 1, pages = 0,
            size = 21 * 1024 * 1024, mtime = 1 } })
        restore_notify()
        restore()
        assert.equals(0, #calls)
        assert.equals(0, #log)
        assert.matches("over 20 MB", messages[1].msg)
        assert.equals(0, #freewrites(root))
        assert.same({}, import.read_manifest(project))
    end)

    it("asks for the folder again on an empty answer, and stops on Esc", function()
        helpers.cleanup(root)
        root = setup(nil)
        local log = run({ "", nil })
        assert.equals(2, #log)
        assert.equals("input", log[2].kind)
        assert.is_nil(project.config_dir("import_dir"))
    end)

    it("refuses a folder inside the project, which every save would commit", function()
        helpers.cleanup(root)
        root = setup(nil)
        vim.fn.mkdir(root .. "boox", "p")
        local _, messages = run({ root .. "boox" })
        assert.matches("outside the project", messages[#messages].msg)
        assert.is_nil(project.config_dir("import_dir"))
    end)

    it("refuses a configured folder inside the project, or one that is gone", function()
        helpers.cleanup(root)
        root = setup(nil)
        vim.fn.mkdir(root .. "boox", "p")
        local config = project.read_file(root .. "config.wyt.yml")
        project.write_file(root .. "config.wyt.yml", config .. "import_dir: '" .. root .. "boox/'\n")
        local log, messages = run({})
        assert.equals(0, #log)
        assert.equals(t("folder_inside"), messages[#messages].msg)

        local gone = (vim.fn.tempname() .. "/gone/"):gsub("\\", "/")
        project.write_file(root .. "config.wyt.yml", config .. "import_dir: '" .. gone .. "'\n")
        _, messages = run({})
        assert.equals(t("folder_missing"):format(gone), messages[#messages].msg)
        assert.equals(0, #freewrites(root))
    end)

    it("opens the first import in Place on Place now", function()
        project.write_file(boox .. "n.txt", "a line\n")
        replies({ "a line" })
        local place = require("wyt.place")
        local open = place.open
        local opened
        place.open = function() opened = vim.fn.expand("%:p") end
        run({ t("import_keep"), t("import_place_now") })
        place.open = open
        assert.truthy(opened:find("freewrite[\\/].*%-n%.md$"))
    end)
end)

local ntfy = require("wyt.ntfy")
-- Stubbed in each spec below and put back at the end of the file.
local poll, download = ntfy.poll, ntfy.download

describe(":WYTImport over ntfy", function()
    local root, fetched, temps
    local URL = "https://ntfy.example/wyt"

    -- The topic holds `messages`; an attachment's bytes are `files[url]`.
    local function topic(messages, files)
        fetched, temps = {}, {}
        ntfy.poll = function(url)
            assert.equals(URL, url)
            return messages
        end
        ntfy.download = function(url, path)
            fetched[#fetched + 1] = url
            temps[#temps + 1] = path
            if not files[url] then return nil, "404" end
            project.write_file(path, files[url])
            return true
        end
    end

    local function file(id, name, extra)
        return vim.tbl_extend("force", { id = id, time = 100, event = "message",
            attachment = { name = name, url = "https://ntfy.example/file/" .. id, size = 10, expires = os.time() + 3600 } }, extra or {})
    end

    before_each(function()
        llm.generate_text = generate_text
        helpers.cleanup(root)
        root = setup(nil)
        local config = project.read_file(root .. "config.wyt.yml")
        project.write_file(root .. "config.wyt.yml", config .. "ntfy: '" .. URL .. "/'\n")
    end)

    it("brings a shared note in, asks for no folder, and not twice", function()
        topic({ { id = "a1", time = 100, event = "message", message = "Teh ferry" } }, {})
        replies({ "The ferry" })
        local log = run({ t("import_use"), t("import_place_later") })
        assert.equals("select", log[1].kind)
        assert.same({ "> Boox: note.txt\n\nThe ferry\n" }, freewrites(root))
        assert.truthy(import.read_manifest(project)["ntfy:a1"])
        assert.is_nil(import.read_manifest(project)["note.txt"])

        local again, messages = run({})
        assert.equals(0, #again)
        assert.equals(t("import_none"):format(URL), messages[#messages].msg)
    end)

    it("reads only the latest share of a notebook, from the page after the last one imported", function()
        project.write_file(root .. "imports.wyt.json", vim.json.encode({ ["Notebook.pdf"] = { pages = 2 } }))
        topic({ file("p1", "Notebook.pdf"), file("p2", "Notebook.pdf") },
            { ["https://ntfy.example/file/p2"] = "%PDF-1.4 fake" })
        local calls = replies({ vim.json.encode({ pages = 4, text = "Page three." }) })
        run({ t("import_it"), t("import_place_later") })
        assert.same({ "https://ntfy.example/file/p2" }, fetched)
        assert.equals(vim.base64.encode("%PDF-1.4 fake"), calls[1].opts.pdf)
        assert.matches("from page 3 to the end", calls[1].prompt)
        assert.same({ "> Boox: Notebook.pdf\n\nPage three.\n" }, freewrites(root))
        assert.equals(0, vim.fn.filereadable(temps[1]))
        local manifest = import.read_manifest(project)
        assert.truthy(manifest["ntfy:p1"])
        assert.truthy(manifest["ntfy:p2"])
        assert.equals(4, manifest["Notebook.pdf"].pages)
    end)

    it("fetches a page only when the run reaches it", function()
        topic({ file("q1", "One.pdf"), file("q2", "Two.pdf") },
            { ["https://ntfy.example/file/q1"] = "%PDF one", ["https://ntfy.example/file/q2"] = "%PDF two" })
        replies({ vim.json.encode({ pages = 1, text = "Page one." }) })
        -- Esc at the first menu: the second is never fetched.
        run({})
        assert.same({ "https://ntfy.example/file/q1" }, fetched)
    end)

    it("brings in only what was added to a shared .txt", function()
        local old = "First line.\n"
        project.write_file(root .. "imports.wyt.json", vim.json.encode({ ["Ferry.txt"] = { bytes = #old, sha = vim.fn.sha256(old) } }))
        topic({ file("t1", "Ferry.txt") }, { ["https://ntfy.example/file/t1"] = old .. "Second line.\n" })
        local calls = replies({ "Second line." })
        run({ t("import_use"), t("import_place_later") })
        assert.matches("<text>\nSecond line.\n</text>", calls[1].prompt)
        assert.same({ "> Boox: Ferry.txt\n\nSecond line.\n" }, freewrites(root))
    end)

    it("takes each note past the size limit as a note, not a notebook shared again", function()
        topic({ file("n1", "attachment.txt"), file("n2", "attachment.txt") },
            { ["https://ntfy.example/file/n1"] = "One.", ["https://ntfy.example/file/n2"] = "Two." })
        replies({ "One.", "Two." })
        run({ t("import_use"), t("import_use"), t("import_place_later") })
        assert.same({ "https://ntfy.example/file/n1", "https://ntfy.example/file/n2" }, fetched)
        local manifest = import.read_manifest(project)
        assert.truthy(manifest["ntfy:n1"])
        assert.truthy(manifest["ntfy:n2"])
        assert.is_nil(manifest["attachment.txt"])
    end)

    it("records a shared .txt with nothing added, and says nothing is new", function()
        local old = "First line.\n"
        project.write_file(root .. "imports.wyt.json", vim.json.encode({ ["Ferry.txt"] = { bytes = #old, sha = vim.fn.sha256(old) } }))
        topic({ file("t2", "Ferry.txt") }, { ["https://ntfy.example/file/t2"] = old })
        local log, messages = run({})
        assert.equals(0, #log)
        assert.equals(t("import_none"):format(URL), messages[#messages].msg)
        assert.truthy(import.read_manifest(project)["ntfy:t2"])
    end)

    it("leaves out the brief it sent and what is neither text nor a page", function()
        topic({ file("b1", "today-notes.pdf", { tags = { ntfy.BRIEF_TAG } }), file("i1", "photo.png") }, {})
        local log, messages = run({})
        assert.equals(0, #log)
        assert.same({}, fetched)
        assert.equals(t("import_none"):format(URL), messages[#messages].msg)
    end)

    it("says once what expired on the server, and skips it", function()
        topic({ file("e1", "Old.pdf", { attachment = { name = "Old.pdf", url = "x", size = 10, expires = os.time() - 1 } }) }, {})
        local _, messages = run({})
        assert.same({}, fetched)
        assert.equals(t("import_expired"):format("Old.pdf"), messages[1].msg)
        assert.truthy(import.read_manifest(project)["ntfy:e1"])
        assert.equals("", vim.system({ "git", "-C", root, "status", "--porcelain", "--", "imports.wyt.json" }, { text = true }):wait().stdout)
        _, messages = run({})
        assert.equals(t("import_none"):format(URL), messages[1].msg)
    end)

    it("warns on a failed fetch and tries it again next time", function()
        topic({ file("f1", "Notebook.pdf") }, {})
        local _, messages = run({})
        assert.matches("^" .. vim.pesc(t("ntfy_failed")) .. "Notebook%.pdf: 404", messages[1].msg)
        assert.is_nil(import.read_manifest(project)["ntfy:f1"])
    end)

    it("does not fetch a .pdf too big to send", function()
        topic({ file("g1", "Big.pdf", { attachment = { name = "Big.pdf", url = "x", size = 21 * 1024 * 1024, expires = os.time() + 60 } }) }, {})
        local _, messages = run({})
        assert.same({}, fetched)
        assert.equals(t("import_too_big"):format("Big.pdf"), messages[1].msg)
    end)

    it("says a .txt is too big too, rather than dropping it as nothing new", function()
        topic({ file("g2", "Big.txt", { attachment = { name = "Big.txt", url = "x", size = 21 * 1024 * 1024, expires = os.time() + 60 } }) }, {})
        local _, messages = run({})
        assert.same({}, fetched)
        assert.equals(t("import_too_big"):format("Big.txt"), messages[1].msg)
        assert.is_nil(import.read_manifest(project)["ntfy:g2"])
    end)

    it("says so when the server cannot be reached", function()
        ntfy.poll = function() return nil, "connection refused" end
        local log, messages = run({})
        assert.equals(0, #log)
        assert.equals(t("ntfy_failed") .. "connection refused", messages[1].msg)
    end)
end)

ntfy.poll, ntfy.download = poll, download
