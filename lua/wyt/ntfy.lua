-- The Boox over ntfy: :WYTBrief sends the PDF to a topic the tablet is
-- subscribed to, and :WYTImport pulls what the tablet shared to it. A topic in
-- place of a synced folder: no folder to find on either side, and a tap on the
-- notification opens the brief. `ntfy:` in the root config is the topic's full
-- URL, so a server of one's own, reached over Tailscale, is the same line.
local M = {}

-- What WYT sends carries this tag, so the import does not read the brief back.
M.BRIEF_TAG = "wyt-brief"

--- The topic URL from the root config, without a trailing slash, or nil; nil
--- and the reason when the key is there but is no URL.
function M.url(project)
    local url = project.config_value(project.read_file(project.config_path), "ntfy")
    if not url then return nil end
    -- Unquoted, the YAML reader stops at the colon and leaves `https`.
    if not url:match("^https?://") then return nil, project.t("ntfy_not_url") end
    return (url:gsub("/+$", ""))
end

-- -f turns an HTTP error, such as an attachment the server already dropped,
-- into a failure rather than an error page saved as the file. The timeouts
-- keep a server that is gone, Tailscale off, from freezing the editor.
local CURL = { "curl", "-sS", "-f", "--proto", "=http,https", "--connect-timeout", "10", "--max-time", "120" }

local function failure(result)
    local err = vim.trim(result.stderr or "")
    return err ~= "" and err or ("exit " .. result.code)
end

-- curl, waited for: the import lists what is new before its first menu, the
-- way it reads a folder.
local function curl(args)
    local cmd = vim.list_extend(vim.list_extend({}, CURL), args)
    local ok, result = pcall(function() return vim.system(cmd, { text = true }):wait() end)
    if not ok then return nil, "curl could not be run: " .. tostring(result) end
    if result.code ~= 0 then return nil, failure(result) end
    return result.stdout
end

--- Send the file at `path` to the topic as `filename`, under `title`, tagged
--- as a brief. `callback(true)` or `callback(nil, err)`, on the main loop.
function M.publish(url, path, filename, title, callback)
    -- As query parameters, URL-encoded: a header would have to carry a title
    -- with accents in an encoding curl and the server agree on. rfc2396, since
    -- the default leaves a `&` or `+` in a title to split the query.
    local query = ("?filename=%s&title=%s&tags=%s"):format(
        vim.uri_encode(filename, "rfc2396"), vim.uri_encode(title, "rfc2396"), M.BRIEF_TAG)
    local cmd = vim.list_extend(vim.list_extend({}, CURL), { "-T", path, "--", url .. query })
    local function done(result)
        vim.schedule(function()
            if result.code == 0 then return callback(true) end
            callback(nil, failure(result))
        end)
    end
    local ok, err = pcall(vim.system, cmd, { text = true }, done)
    if not ok then done({ code = -1, stderr = "curl could not be run: " .. tostring(err) }) end
end

--- Every message the server still holds for the topic, oldest first, or nil
--- and the reason.
function M.poll(url)
    local out, err = curl({ "--", url .. "/json?poll=1&since=all" })
    if not out then return nil, err end
    local messages = {}
    for line in out:gmatch("[^\r\n]+") do
        local ok, m = pcall(vim.json.decode, line)
        if ok and type(m) == "table" and m.event == "message" then messages[#messages + 1] = m end
    end
    return messages
end

--- Save the attachment at `url` to `path`, refusing more than `max` bytes.
--- True, or nil and the reason.
function M.download(url, path, max)
    -- The URL is the server's word, not ours: anything but http(s) could be a
    -- local file, or an option to curl.
    if type(url) ~= "string" or not url:match("^https?://") then return nil, "not an http(s) URL: " .. tostring(url) end
    local out, err = curl({ "--max-filesize", tostring(max), "-o", path, "--", url })
    return out and true, err
end

return M
