local M = {}

M.options = {
    llm_provider = "openai", -- "openai" o "claude"
    -- string | function(): string
    -- A function is resolved lazily, on the first LLM request. See wyt.secret.
    api_key = "",
}

-- Resolved secret, cached for the session. Deliberately NOT kept in M.options:
-- that table is inspected by :checkhealth and is the obvious thing to dump with
-- :lua vim.print(require("wyt.config").options), so the key must never live there.
local resolved_key = nil

function M.setup(opts)
    M.options = vim.tbl_deep_extend("force", M.options, opts or {})
    resolved_key = nil -- a config change invalidates the cached secret
end

--- Resolve the API key, invoking the resolver function on first use.
--- @return string|nil key, string|nil err
function M.get_api_key()
    if resolved_key and resolved_key ~= "" then
        return resolved_key
    end

    local spec = M.options.api_key

    if type(spec) == "function" then
        local ok, value = pcall(spec)
        if not ok then
            return nil, "api_key resolver failed: " .. tostring(value)
        end
        if type(value) ~= "string" or value == "" then
            return nil, "api_key resolver returned an empty value"
        end
        resolved_key = value
    elseif type(spec) == "string" and spec ~= "" then
        resolved_key = spec
    else
        return nil, nil -- not configured at all; caller reports the usual message
    end

    return resolved_key
end

--- Drop the cached secret (e.g. after locking the machine, or to re-prompt).
function M.clear_api_key()
    resolved_key = nil
end

--- Where the key comes from, for diagnostics. Never returns the key itself.
--- @return string one of "resolver", "literal", "unset"
function M.api_key_source()
    local spec = M.options.api_key
    if type(spec) == "function" then
        return "resolver"
    elseif type(spec) == "string" and spec ~= "" then
        return "literal"
    end
    return "unset"
end

return M
