-- Lazy API-key resolvers.
--
-- Each function here returns a `function(): string` suitable for passing as
-- `api_key` to `require("wyt").setup()`. The resolver is invoked only when a
-- request is actually made (see wyt.config.get_api_key), and the result is
-- cached in memory for the session.
--
-- Why not an environment variable: a user-scoped env var is inherited by every
-- process Neovim spawns (LSP servers, formatters, build scripts, terminal
-- jobs), and it shows up in crash dumps and in the output of `env`. A resolver is
-- read on demand, by this plugin only.
local M = {}

-- Run a command and return its trimmed stdout.
-- Synchronous by design: this happens once, on the first LLM call.
local function run(cmd)
    local ok, res = pcall(function()
        -- A helper that decides to prompt (an expired unlock, a device that
        -- is not there) would otherwise hold Neovim still with no way out.
        return vim.system(cmd, { text = true, timeout = 15000 }):wait()
    end)
    if not ok then
        return nil, tostring(res)
    end
    if res.code ~= 0 then
        local stderr = (res.stderr or ""):gsub("%s+$", "")
        return nil, stderr ~= "" and stderr or ("exit code " .. res.code)
    end
    local out = (res.stdout or ""):gsub("[\r\n]+$", "")
    return out
end

--- Generic resolver: run `cmd` and use its stdout as the secret.
--- @param cmd table argv list, e.g. { "pass", "show", "anthropic" }
function M.command(cmd)
    return function()
        local out, err = run(cmd)
        if not out or out == "" then
            error("no secret returned by " .. table.concat(cmd, " ") .. (err and (": " .. err) or ""), 0)
        end
        return out
    end
end

--- macOS Keychain. Store first with:
---   security add-generic-password -s wyt -a "$USER" -w
--- @param service string keychain service name (default "wyt")
--- @param account string|nil keychain account (default $USER)
function M.keychain(service, account)
    return M.command({
        "security", "find-generic-password", "-w",
        "-s", service or "wyt",
        "-a", account or vim.env.USER or "default",
    })
end

--- Linux libsecret / gnome-keyring. Store first with:
---   secret-tool store --label="WYT" service wyt account default
--- @param service string default "wyt"
--- @param account string|nil default "default"
function M.libsecret(service, account)
    return M.command({
        "secret-tool", "lookup",
        "service", service or "wyt",
        "account", account or "default",
    })
end

--- Default path for the Windows DPAPI-protected key file.
function M.dpapi_path()
    return vim.fs.normalize(vim.fn.stdpath("data") .. "/wyt/api_key.dpapi")
end

--- Windows DPAPI. The file holds ciphertext bound to the current user account
--- on the current machine: copying it elsewhere yields nothing. Store it with
--- the snippet in README.md, "Guardar la key" (it uses Read-Host, so the key
--- never enters your shell history).
--- @param path string|nil defaults to M.dpapi_path()
function M.dpapi(path)
    path = path or M.dpapi_path()
    local ps = vim.fn.executable("pwsh") == 1 and "pwsh" or "powershell"
    -- A single-quoted PowerShell literal, not Lua's %q: PowerShell expands $var
    -- inside double quotes, and a path is allowed to contain a dollar sign.
    local literal = "'" .. path:gsub("'", "''") .. "'"
    -- Read the single ciphertext line, unprotect it via DPAPI, write plaintext
    -- to stdout. The key is never an argument to any process.
    local script = table.concat({
        "$ErrorActionPreference = 'Stop';",
        "$enc = Get-Content -LiteralPath " .. literal .. " -TotalCount 1;",
        "$sec = ConvertTo-SecureString $enc;",
        "$b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec);",
        "try { [Runtime.InteropServices.Marshal]::PtrToStringAuto($b) }",
        "finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }",
    }, " ")
    return M.command({ ps, "-NoProfile", "-NonInteractive", "-Command", script })
end

--- Read the first line of a plain file. Weakest of the stored options: use
--- only with restrictive permissions (chmod 600) and never inside a git repo.
--- @param path string
function M.file(path)
    -- io.open takes the path literally, so "~/.wyt-key" would never be found.
    path = vim.fs.normalize(path)
    return function()
        local fd = io.open(path, "r")
        if not fd then
            error("cannot open key file: " .. path, 0)
        end
        local line = fd:read("l")
        fd:close()
        if not line or line == "" then
            error("key file is empty: " .. path, 0)
        end
        return (line:gsub("%s+$", ""))
    end
end

--- Environment variable. Kept for convenience, but see the note at the top of
--- this file: prefer a credential store for anything long-lived.
--- @param name string default "ANTHROPIC_API_KEY"
function M.env(name)
    name = name or "ANTHROPIC_API_KEY"
    return function()
        local value = vim.env[name]
        if not value or value == "" then
            error("environment variable " .. name .. " is not set", 0)
        end
        return value
    end
end

--- Ask once per Neovim session, with no echo and nothing written to disk.
--- The strongest option at rest, at the cost of typing it each session.
--- @param label string|nil prompt text
function M.prompt(label)
    return function()
        local value = vim.fn.inputsecret(label or "WYT API key: ")
        if not value or value == "" then
            error("no key entered", 0)
        end
        return value
    end
end

--- Pick the native credential store for the current OS, falling back to an
--- interactive prompt where none is available.
--- @param service string|nil default "wyt"
function M.os_store(service)
    if vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1 then
        return M.dpapi()
    elseif vim.fn.has("mac") == 1 then
        return M.keychain(service)
    elseif vim.fn.executable("secret-tool") == 1 then
        return M.libsecret(service)
    end
    return M.prompt()
end

return M
