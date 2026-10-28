-- :WYTBrief writes Today's brief as a PDF outside the project. The model is
-- stubbed; what is checked is the folder question, where the file lands, and
-- that the brief and the menu reach it.
local helpers = require("tests.helpers")
local project = require("wyt.project")
local brief = require("wyt.brief")
local llm = require("wyt.llm")
local pdf = require("wyt.pdf")
-- Every spec stubs it in before_each; the runner has no after_each, so the
-- end of the file puts it back.
local today = llm.today

local function t(k) return require("wyt.localization").t(k, "en") end

local function setup(dir)
    local root = helpers.project({ sections = false, name = "Notes" })
    if dir then
        local config = project.read_file(root .. "config.wyt.yml")
        project.write_file(root .. "config.wyt.yml", config .. "brief_dir: '" .. dir .. "'\n")
    end
    vim.system({ "git", "-C", root, "init", "-q" }):wait()
    return root
end

local function outside()
    local dir = (vim.fn.tempname() .. "/boox/"):gsub("\\", "/")
    vim.fn.mkdir(dir, "p")
    return dir
end

local function run(answers)
    local log, restore = helpers.scripted_ui(answers)
    local messages, restore_notify = helpers.capture_notify()
    brief.open()
    restore_notify()
    restore()
    return log, messages
end

local function written(dir)
    local names = vim.fn.readdir(dir)
    return names, names[1] and project.read_file(dir .. names[1])
end

describe(":WYTBrief", function()
    local root
    before_each(function()
        helpers.cleanup(root)
        llm.today = function(_, cb) cb({ summary = "A story so far.", prompt = "Write the lighthouse." }) end
    end)

    it("asks for the folder the first time, keeps it, and writes the brief there", function()
        root = setup()
        local dir = outside()
        local log, messages = run({ dir })
        assert.equals("input", log[1].kind)
        assert.equals(dir, project.config_dir("brief_dir"))
        assert.matches("brief_dir: '" .. vim.pesc(dir) .. "'", project.read_file(root .. "config.wyt.yml"))
        local names, bytes = written(dir)
        assert.same({ "today-notes.pdf" }, names)
        assert.equals("%PDF", bytes:sub(1, 4))
        assert.truthy(bytes:find(pdf.encode("Write the lighthouse."), 1, true))
        assert.truthy(bytes:find("/F2 15 Tf %d+ [%d.]+ Td %(" .. vim.pesc(t("brief_start")) .. "%) Tj"))
        assert.truthy(bytes:find("/F2 15 Tf %d+ [%d.]+ Td %(" .. vim.pesc(t("brief_prompt")) .. "%) Tj"))
        assert.truthy(bytes:find(pdf.encode("- " .. t("today_freewrite_prompt")), 1, true))
        assert.equals(t("brief_done"):format(dir .. "today-notes.pdf"), messages[#messages].msg)
    end)

    it("uses the configured folder without asking", function()
        local dir = outside()
        root = setup(dir)
        local log = run({})
        assert.equals(0, #log)
        assert.same({ "today-notes.pdf" }, (written(dir)))
    end)

    it("asks again on an empty answer, and does nothing on Esc", function()
        root = setup()
        local llm_called = false
        llm.today = function() llm_called = true end
        -- The second ask finds the answers spent, which reads as Esc.
        local log = run({ "" })
        assert.equals(2, #log)
        assert.is_nil(project.config_dir("brief_dir"))
        assert.falsy(llm_called)
    end)

    it("refuses a missing folder, typed or configured", function()
        root = setup()
        local gone = (vim.fn.tempname() .. "/gone/"):gsub("\\", "/")
        local _, messages = run({ gone })
        assert.equals(t("folder_missing"):format(gone), messages[#messages].msg)
        assert.is_nil(project.config_dir("brief_dir"))

        helpers.cleanup(root)
        root = setup(gone)
        local log
        log, messages = run({})
        assert.equals(0, #log)
        assert.equals(t("folder_missing"):format(gone), messages[#messages].msg)
    end)

    it("refuses a configured folder inside the project", function()
        root = setup()
        vim.fn.mkdir(root .. "boox", "p")
        local config = project.read_file(root .. "config.wyt.yml")
        project.write_file(root .. "config.wyt.yml", config .. "brief_dir: '" .. root .. "boox/'\n")
        local _, messages = run({})
        assert.equals(t("folder_inside"), messages[#messages].msg)
        assert.same({}, vim.fn.readdir(root .. "boox"))
    end)

    it("refuses a folder inside the project", function()
        root = setup()
        vim.fn.mkdir(root .. "boox", "p")
        local _, messages = run({ root .. "boox" })
        assert.is_nil(project.config_dir("brief_dir"))
        assert.equals(t("folder_inside"), messages[#messages].msg)
        assert.same({}, vim.fn.readdir(root .. "boox"))
    end)

    it("refuses the import folder, and takes a subfolder of it", function()
        root = setup()
        local boox = outside()
        local config = project.read_file(root .. "config.wyt.yml")
        project.write_file(root .. "config.wyt.yml", config .. "import_dir: '" .. boox .. "'\n")
        local _, messages = run({ boox })
        assert.equals(t("folder_shared"), messages[#messages].msg)
        assert.is_nil(project.config_dir("brief_dir"))
        assert.same({}, vim.fn.readdir(boox))

        vim.fn.mkdir(boox .. "briefs", "p")
        run({ boox .. "briefs" })
        assert.equals(boox .. "briefs/", project.config_dir("brief_dir"))
        assert.equals(boox, project.config_dir("import_dir"))
        assert.same({ "today-notes.pdf" }, (written(boox .. "briefs/")))
    end)

    it("still writes what came from disk when the model fails", function()
        local dir = outside()
        root = setup(dir)
        llm.today = function(_, cb) cb(nil, "offline") end
        local _, messages = run({})
        local _, bytes = written(dir)
        assert.truthy(bytes:find(pdf.encode(t("today_nothing_yet")), 1, true))
        assert.truthy(bytes:find(pdf.encode("- " .. t("today_freewrite")), 1, true))
        local warned = vim.tbl_filter(function(m) return m.msg == t("today_no_ai") .. "offline" end, messages)
        assert.equals(1, #warned)
    end)
end)

llm.today = today
