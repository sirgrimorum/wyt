-- P1: real async LLM calls via curl (vim.system)
-- All public functions are async: they accept a callback(result, err)
local M = {}

local function get_opts()
    local config = require("wyt.config")
    local key, err = config.get_api_key()
    return config.options.llm_provider, key, err
end

-- Quote a value for curl's config-file syntax. vim.json.encode never emits raw
-- control characters, so escaping backslash and double quote is sufficient.
local function curl_quote(s)
    local escaped = s:gsub("\\", "\\\\"):gsub('"', '\\"')
    return '"' .. escaped .. '"'
end

-- Build a curl invocation that keeps the API key off the command line.
--
-- Anything passed in argv is world-readable while the process lives (`ps aux`,
-- Win32_Process.CommandLine), so the key, and the request body with it, go over
-- stdin via `--config -` instead. Only the flags below are ever visible.
local function curl_request(url, headers, body, callback)
    local lines = { "url = " .. curl_quote(url) }
    for _, h in ipairs(headers) do
        table.insert(lines, "header = " .. curl_quote(h))
    end
    table.insert(lines, "data-binary = " .. curl_quote(body))

    vim.system(
        { "curl", "-s", "--config", "-" },
        { text = true, stdin = table.concat(lines, "\n") .. "\n" },
        callback
    )
end

-- Shared response handling for both providers.
-- `extract` pulls the assistant text out of a decoded, error-free payload.
local function handle_response(result, callback, extract)
    vim.schedule(function()
        if result.code ~= 0 then
            callback(nil, "curl error: " .. (result.stderr or "exit " .. result.code))
            return
        end
        local ok, data = pcall(vim.json.decode, result.stdout)
        if not ok then
            callback(nil, "JSON parse error: " .. tostring(data))
            return
        end
        if data.error then
            local message = data.error.message or vim.inspect(data.error)
            callback(nil, data.error.type and (data.error.type .. ": " .. message) or message)
            return
        end
        callback(extract(data) or "", nil)
    end)
end

-- Internal: call OpenAI chat completions endpoint
local function call_openai(prompt, api_key, callback)
    local body = vim.json.encode({
        model = "gpt-4o",
        messages = { { role = "user", content = prompt } },
        max_tokens = 1024,
    })
    curl_request(
        "https://api.openai.com/v1/chat/completions",
        {
            "Content-Type: application/json",
            "Authorization: Bearer " .. api_key,
        },
        body,
        function(result)
            handle_response(result, callback, function(data)
                return data.choices
                    and data.choices[1]
                    and data.choices[1].message
                    and data.choices[1].message.content
            end)
        end
    )
end

-- Internal: call Anthropic Messages endpoint
local function call_claude(prompt, api_key, callback)
    local body = vim.json.encode({
        model = "claude-opus-4-6",
        max_tokens = 1024,
        messages = { { role = "user", content = prompt } },
    })
    curl_request(
        "https://api.anthropic.com/v1/messages",
        {
            "Content-Type: application/json",
            "x-api-key: " .. api_key,
            "anthropic-version: 2023-06-01",
        },
        body,
        function(result)
            handle_response(result, callback, function(data)
                return data.content and data.content[1] and data.content[1].text
            end)
        end
    )
end

-- Public async API: callback(result_string, err_string_or_nil)
function M.generate_text(prompt, callback)
    local provider, api_key, key_err = get_opts()

    if key_err then
        -- The resolver ran and failed (keychain locked, file missing, ...).
        -- Report that rather than the generic "no key configured" message.
        if callback then
            callback(nil, key_err)
        end
        return
    end

    if not api_key or api_key == "" then
        if callback then
            callback(nil, require("wyt.localization").t("llm_no_api_key"))
        end
        return
    end

    if provider == "openai" then
        call_openai(prompt, api_key, callback)
    elseif provider == "claude" then
        call_claude(prompt, api_key, callback)
    else
        if callback then
            callback(nil, require("wyt.localization").t("provider_not_supported"))
        end
    end
end

-- Ideas and group names are stored as a single `- ` bullet / `## ` header, and
-- add_item_to_section strips newlines without inserting spaces. A chatty reply
-- ("Claro, aquí tienes:\n\n\"...\"") therefore lands in plan.wyt.md as one
-- mangled run-on line, so every short answer is collapsed to one clean line.

local function first_meaningful_line(text)
    text = text:gsub("```[%w]*\n?", "")
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        line = vim.trim(line)
        -- skip blanks and preamble ("Here you go:", "Idea reescrita:")
        if line ~= "" and not line:match(":%s*$") then
            return line
        end
    end
    return vim.trim((text:gsub("%s+", " ")))
end

local function strip_decoration(line)
    line = line:gsub("^%s*[-*•]%s+", "")        -- bullet marker
    line = line:gsub("^%s*%d+[%.%)]%s+", "")    -- "1. " / "1) "
    line = line:gsub("^%*+(.-)%*+$", "%1")      -- **bold**
    line = line:gsub('^["\'“”«]+', '')
    line = line:gsub('["\'“”»]+$', '')
    return vim.trim(line)
end

--- Collapse an LLM reply to the single clean line the caller can store.
function M.to_single_line(text)
    if not text or text == "" then return "" end
    return (strip_decoration(first_meaningful_line(text)):gsub("%s+", " "))
end

--- True when a reply is a clarifying question rather than the answer. The model
--- has no one to ask — the caller keeps the user's own text instead.
function M.looks_like_question(text)
    if not text then return false end
    return text:match("%?%s*$") ~= nil or text:match("^%s*¿") ~= nil
end

-- Convenience wrapper: improve a single idea sentence.
-- `context` is optional project context (type, description).
function M.improve_idea(idea_text, lang, callback, context)
    local parts = {}
    if lang == "es" then
        parts[#parts + 1] = "Reescribe la idea delimitada por <idea> como UNA sola oración clara y concisa en español."
        if context and context ~= "" then
            parts[#parts + 1] = "Contexto del proyecto: " .. context
        end
        parts[#parts + 1] = "Responde únicamente con la oración reescrita, en una sola línea."
        parts[#parts + 1] = "No añadas introducción, comillas, viñetas, explicaciones ni comentarios."
        parts[#parts + 1] = "No pidas aclaraciones ni hagas preguntas: si la idea es vaga, reescríbela tal como está."
    else
        parts[#parts + 1] = "Rewrite the idea delimited by <idea> as ONE clear, concise sentence in English."
        if context and context ~= "" then
            parts[#parts + 1] = "Project context: " .. context
        end
        parts[#parts + 1] = "Reply with the rewritten sentence only, on a single line."
        parts[#parts + 1] = "Do not add preamble, quotes, bullets, explanations or commentary."
        parts[#parts + 1] = "Never ask for clarification: if the idea is vague, rewrite it as it stands."
    end
    parts[#parts + 1] = "<idea>" .. idea_text .. "</idea>"

    M.generate_text(table.concat(parts, "\n"), function(result, err)
        if err or not result then
            callback(nil, err)
            return
        end
        callback(M.to_single_line(result), nil)
    end)
end

-- Generate a paragraph from an idea
function M.expand_idea(idea_text, context, lang, callback)
    local prompt
    if lang == "es" then
        prompt = "Escribe un párrafo literario sobre la siguiente idea"
        if context and context ~= "" then
            prompt = prompt .. ". Contexto del proyecto: " .. context
        end
        prompt = prompt .. ". Idea: " .. idea_text
    else
        prompt = "Write a literary paragraph based on the following idea"
        if context and context ~= "" then
            prompt = prompt .. ". Project context: " .. context
        end
        prompt = prompt .. ". Idea: " .. idea_text
    end
    M.generate_text(prompt, callback)
end

-- Suggest a group name from a list of ideas
function M.suggest_group_name(ideas, type_name, lang, callback)
    local ideas_str = table.concat(ideas, "\n- ")
    local prompt
    if lang == "es" then
        prompt = "Sugiere un nombre corto y descriptivo para un grupo de ideas de un " .. type_name
            .. ".\nIdeas:\n- " .. ideas_str
            .. "\nResponde solo con el nombre, en una sola línea, sin comillas, sin prefijos"
            .. " como \"Nombre:\" y sin explicación."
    else
        prompt = "Suggest a short, descriptive name for a group of ideas in a " .. type_name
            .. ".\nIdeas:\n- " .. ideas_str
            .. "\nReply with the name only, on a single line, no quotes, no \"Name:\" prefix,"
            .. " no explanation."
    end
    M.generate_text(prompt, function(result, err)
        if err or not result then
            callback(nil, err)
            return
        end
        callback(M.to_single_line(result), nil)
    end)
end

return M
