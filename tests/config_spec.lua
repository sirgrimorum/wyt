-- The API key's life: resolved on the first request, cached for the session,
-- never kept where :checkhealth or vim.print(options) would show it. The OS
-- stores need the real OS; the resolvers that read a file, a variable or a
-- command's output are plain enough to run here.
local helpers = require("tests.helpers")
local config = require("wyt.config")
local secret = require("wyt.secret")

describe("config.get_api_key", function()
    before_each(function() config.setup({ llm_provider = "openai", api_key = "" }) end)

    it("calls a resolver once, however many requests follow", function()
        local calls = 0
        config.setup({ api_key = function() calls = calls + 1; return "sk-test" end })
        assert.equals("sk-test", config.get_api_key())
        assert.equals("sk-test", config.get_api_key())
        assert.equals(1, calls)
    end)

    it("asks the resolver again after setup changes the config", function()
        local calls = 0
        config.setup({ api_key = function() calls = calls + 1; return "sk-test" end })
        config.get_api_key()
        config.setup({ llm_provider = "claude" })
        config.get_api_key()
        assert.equals(2, calls)
    end)

    it("reports a resolver that throws instead of throwing itself", function()
        config.setup({ api_key = function() error("locked", 0) end })
        local key, err = config.get_api_key()
        assert.is_nil(key)
        assert.matches("resolver failed: locked", err)
    end)

    it("treats an empty resolver answer as an error, not a key", function()
        config.setup({ api_key = function() return "" end })
        local key, err = config.get_api_key()
        assert.is_nil(key)
        assert.matches("empty", err)
    end)
end)

describe(":WYTConfig", function()
    before_each(function()
        config.setup({ llm_provider = "openai", api_key = "" })
        require("wyt.commands").setup()
    end)

    it("keeps a typed key out of config.options", function()
        helpers.capture_notify()
        vim.cmd("WYTConfig claude sk-typed")
        assert.equals("function", type(config.options.api_key))
        assert.equals("resolver", config.api_key_source())
        assert.equals("sk-typed", config.get_api_key())
    end)

    -- The command history goes to the shada file, so a key typed there outlives
    -- the session. Deleting the newest entry blind took the writer's own last
    -- command with it whenever :WYTConfig ran from a mapping or a script.
    it("takes the typed key out of the history without touching the rest", function()
        helpers.capture_notify()
        vim.fn.histdel("cmd")
        vim.fn.histadd("cmd", "WYTConfig claude sk-typed")
        vim.fn.histadd("cmd", "write")
        vim.cmd("WYTConfig claude sk-typed")
        assert.equals("write", vim.fn.histget("cmd", -1))
        local entries = {}
        for i = 1, vim.fn.histnr("cmd") do entries[#entries + 1] = vim.fn.histget("cmd", i) end
        assert.has_no_match("sk%-typed", table.concat(entries, "\n"))
    end)
end)

describe("wyt.secret resolvers", function()
    local dir

    before_each(function()
        if dir then vim.fn.delete(dir, "rf") end
        dir = vim.fn.tempname()
        vim.fn.mkdir(dir, "p")
    end)

    it("reads the first line of a key file, trimmed", function()
        helpers.write(dir .. "/key", "sk-file  \nsecond line\n")
        assert.equals("sk-file", secret.file(dir .. "/key")())
    end)

    it("expands the path, so the README's ~/.wyt-key form works", function()
        helpers.write(dir .. "/key", "sk-file\n")
        vim.env.WYT_TEST_DIR = dir
        local ok, value = pcall(secret.file("$WYT_TEST_DIR/key"))
        vim.env.WYT_TEST_DIR = nil
        assert(ok, value)
        assert.equals("sk-file", value)
    end)

    it("errors on a missing or empty key file", function()
        assert.falsy(pcall(secret.file(dir .. "/absent")))
        helpers.write(dir .. "/empty", "")
        assert.falsy(pcall(secret.file(dir .. "/empty")))
    end)

    it("errors on an unset environment variable", function()
        vim.env.WYT_TEST_UNSET = nil
        assert.falsy(pcall(secret.env("WYT_TEST_UNSET")))
    end)

    it("uses a command's stdout, without the trailing newline", function()
        local cmd = vim.fn.has("win32") == 1 and { "cmd", "/c", "echo sk-cmd" } or { "echo", "sk-cmd" }
        assert.equals("sk-cmd", vim.trim(secret.command(cmd)()))
    end)
end)

describe("wyt.secret.dpapi", function()
    -- PowerShell expands $var inside double quotes, and %q quotes that way.
    it("puts the path in a single-quoted PowerShell literal", function()
        local cmd
        local system = vim.system
        vim.system = function(argv) cmd = argv; error("not run", 0) end
        pcall(secret.dpapi("D:/keys/$env/api.dpapi"))
        vim.system = system
        local script = cmd[#cmd]
        assert.matches("-LiteralPath 'D:/keys/%$env/api%.dpapi'", script)
    end)

    it("doubles a quote in the path rather than closing the literal", function()
        local cmd
        local system = vim.system
        vim.system = function(argv) cmd = argv; error("not run", 0) end
        pcall(secret.dpapi("D:/it's/api.dpapi"))
        vim.system = system
        assert.matches("'D:/it''s/api%.dpapi'", cmd[#cmd])
    end)
end)

describe("the curl config the key travels in", function()
    -- The key is not JSON: a newline pasted in with it used to end the header
    -- line, and curl read the rest as another option.
    it("escapes a newline inside the key instead of starting a new option", function()
        config.setup({ llm_provider = "claude", api_key = "sk-one\noutput = D:/owned.txt" })
        local stdin
        local system = vim.system
        vim.system = function(_, opts) stdin = opts.stdin; error("not run", 0) end
        local reported
        require("wyt.llm").generate_text("hola", function(_, err) reported = err end)
        vim.system = system
        -- The failure path hands the response handler a finished process, and
        -- that reply is scheduled: let it run before reading it back.
        vim.wait(100, function() return reported ~= nil end)
        assert.matches("curl could not be run", reported)
        assert.has_no_match("\noutput", stdin)
        assert.matches('\\noutput', stdin, 1, true)
    end)
end)
