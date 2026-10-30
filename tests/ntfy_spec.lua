-- wyt.ntfy is curl and nothing else, so vim.system is stubbed: what is checked
-- is the command each call runs and how the topic's reply is read.
local helpers = require("tests.helpers")
local project = require("wyt.project")
local ntfy = require("wyt.ntfy")
local system = vim.system

-- vim.system answering `reply`, and the commands it was given.
local function curl(reply)
    local cmds = {}
    vim.system = function(cmd, _, on_exit)
        cmds[#cmds + 1] = cmd
        local result = vim.tbl_extend("force", { code = 0, stdout = "", stderr = "" }, reply)
        if on_exit then return on_exit(result) end
        return { wait = function() return result end }
    end
    return cmds
end

describe("ntfy.url", function()
    local root
    before_each(function() helpers.cleanup(root) end)

    it("reads the quoted topic URL from the root config, without the trailing slash", function()
        root = helpers.project({ sections = false, name = "Notes" })
        assert.is_nil(ntfy.url(project))
        local config = project.read_file(root .. "config.wyt.yml")
        project.write_file(root .. "config.wyt.yml", config .. "ntfy: 'https://pc.tail1.ts.net/wyt-x/'\n")
        assert.equals("https://pc.tail1.ts.net/wyt-x", ntfy.url(project))
    end)

    it("says to quote a URL the config reader cut at the colon", function()
        root = helpers.project({ sections = false, name = "Notes" })
        local config = project.read_file(root .. "config.wyt.yml")
        project.write_file(root .. "config.wyt.yml", config .. "ntfy: https://pc.tail1.ts.net/wyt-x\n")
        local url, err = ntfy.url(project)
        assert.is_nil(url)
        assert.equals(project.t("ntfy_not_url"), err)
    end)
end)

describe("ntfy over curl", function()
    before_each(function() vim.system = system end)

    it("publishes the file with its name, an encoded title and the brief tag", function()
        local cmds = curl({})
        local got
        ntfy.publish("https://n.example/t", "/tmp/b.pdf", "today-el-faro.pdf", "Sal & mar+1: día 3", function(ok) got = ok end)
        vim.wait(100, function() return got ~= nil end)
        assert.truthy(got)
        local cmd = cmds[1]
        assert.equals("/tmp/b.pdf", cmd[#cmd - 2])
        assert.equals("--", cmd[#cmd - 1])
        assert.equals("https://n.example/t?filename=today-el-faro.pdf&title=Sal%20%26%20mar%2b1%3a%20d%c3%ada%203&tags=wyt-brief", cmd[#cmd])
    end)

    it("downloads to the path, no bigger than asked", function()
        local cmds = curl({})
        assert.truthy(ntfy.download("https://n.example/file/a", "/tmp/a.pdf", 20))
        local cmd = table.concat(cmds[1], " ")
        assert.matches("%-%-max%-filesize 20 %-o /tmp/a%.pdf %-%- https://n%.example/file/a$", cmd)
        assert.matches("%-%-proto =http,https", cmd)
    end)

    it("refuses an attachment URL that is not http(s), without running curl", function()
        local cmds = curl({})
        for _, url in ipairs({ "-K//evil/cfg", "file:///C:/Users/me/.ssh/id_rsa", vim.NIL }) do
            local ok, err = ntfy.download(url, "/tmp/a.pdf", 20)
            assert.is_nil(ok)
            assert.matches("^not an http%(s%) URL", err)
        end
        assert.equals(0, #cmds)
    end)

    it("hands curl's error to the callback", function()
        curl({ code = 22, stderr = "curl: (22) 403\n" })
        local got, err
        ntfy.publish("https://n.example/t", "/tmp/b.pdf", "b.pdf", "b", function(ok, e) got, err = ok, e end)
        vim.wait(100, function() return err ~= nil end)
        assert.is_nil(got)
        assert.equals("curl: (22) 403", err)
    end)

    it("says so when curl cannot be run, to the callback and to a caller", function()
        vim.system = function() error("ENOENT") end
        local got, err
        ntfy.publish("https://n.example/t", "/tmp/b.pdf", "b.pdf", "b", function(ok, e) got, err = ok, e end)
        vim.wait(100, function() return err ~= nil end)
        assert.is_nil(got)
        assert.matches("^curl could not be run", err)
        local messages, perr = ntfy.poll("https://n.example/t")
        assert.is_nil(messages)
        assert.matches("^curl could not be run", perr)
    end)

    it("polls every message the topic holds, and keeps only messages", function()
        local cmds = curl({ stdout = '{"id":"a","event":"open"}\n{"id":"b","event":"message","message":"hi"}\r\nnot json\n' })
        local messages = ntfy.poll("https://n.example/t")
        assert.equals("https://n.example/t/json?poll=1&since=all", cmds[1][#cmds[1]])
        assert.equals(1, #messages)
        assert.equals("hi", messages[1].message)
    end)

    it("returns nil and the reason when the server cannot be reached", function()
        curl({ code = 7, stderr = "curl: (7) Failed to connect\n" })
        local messages, err = ntfy.poll("https://n.example/t")
        assert.is_nil(messages)
        assert.equals("curl: (7) Failed to connect", err)
    end)
end)

vim.system = system
