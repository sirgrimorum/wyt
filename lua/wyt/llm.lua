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

-- Lua patterns are byte-oriented, so a character class holding multibyte
-- punctuation ("«", "•") also matches those characters' individual bytes. `¿`
-- is 0xC2 0xBF and `«` is 0xC2 0xAB, so `[«]` ate the 0xC2 off every Spanish
-- question, leaving a broken byte. Quote and bullet markers are matched as
-- whole tokens instead.
local BULLETS = { "- ", "* ", "• ", "– ", "— " }
local OPEN_QUOTES = { '"', "'", "“", "«", "‘" }
local CLOSE_QUOTES = { '"', "'", "”", "»", "’" }

local function strip_wrapping_quotes(s)
    local changed = true
    while changed do
        changed = false
        for _, q in ipairs(OPEN_QUOTES) do
            if s:sub(1, #q) == q then
                s = s:sub(#q + 1)
                changed = true
            end
        end
        for _, q in ipairs(CLOSE_QUOTES) do
            if #s >= #q and s:sub(-#q) == q then
                s = s:sub(1, #s - #q)
                changed = true
            end
        end
    end
    return s
end

local function strip_decoration(line)
    line = vim.trim(line)
    for _, b in ipairs(BULLETS) do
        if line:sub(1, #b) == b then
            line = vim.trim(line:sub(#b + 1))
            break
        end
    end
    line = line:gsub("^%d+[%.%)]%s+", "")       -- "1. " / "1) "
    line = line:gsub("^%*%*(.-)%*%*$", "%1")    -- **bold**
    line = line:gsub("^%*(.-)%*$", "%1")        -- *italic*
    return vim.trim(strip_wrapping_quotes(line))
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

-- Pull the first JSON object out of a reply that may still carry fences or prose.
local function extract_json(text)
    text = text:gsub("```%w*", ""):gsub("```", "")
    local first = text:find("{", 1, true)
    local last = text:reverse():find("}", 1, true)
    if not first or not last then return nil end
    local ok, data = pcall(vim.json.decode, text:sub(first, #text - last + 1))
    if ok and type(data) == "table" then return data end
    return nil
end

-- A clarifying question is only useful if it can be answered from a menu, so
-- the options are capped in both count and length before they reach the UI.
local function normalize_options(list)
    if type(list) ~= "table" then return nil end
    local out = {}
    for _, v in ipairs(list) do
        if type(v) == "string" then
            local words = {}
            for w in M.to_single_line(v):gmatch("%S+") do
                words[#words + 1] = w
                if #words == 4 then break end
            end
            local option = table.concat(words, " ")
            if option ~= "" then out[#out + 1] = option end
        end
        if #out == 4 then break end
    end
    -- one option is not a choice; fall through to the plain-text path instead
    if #out < 2 then return nil end
    return out
end

local function build_improve_prompt(idea_text, lang, opts)
    local p = {}
    if lang == "es" then
        p[#p + 1] = "Reescribe la idea delimitada por <idea> como UNA sola oración clara y concisa en español."
        if opts.context and opts.context ~= "" then
            p[#p + 1] = "Contexto del proyecto: " .. opts.context
        end
        for _, qa in ipairs(opts.answers or {}) do
            p[#p + 1] = "Ya preguntaste: " .. qa.question .. " El autor respondió: " .. qa.answer
        end
        if opts.avoid and opts.avoid ~= "" then
            p[#p + 1] = "Propón una versión claramente distinta de esta: " .. opts.avoid
        end
        p[#p + 1] = "Responde SOLO con un objeto JSON, sin texto adicional ni bloques de código."
        if opts.no_questions then
            p[#p + 1] = 'Formato obligatorio: {"idea": "la oración reescrita"}. No hagas preguntas.'
        else
            p[#p + 1] = 'Formato normal: {"idea": "la oración reescrita"}.'
            p[#p + 1] = "Prefiere reescribir. Solo si la idea es imposible de interpretar, responde:"
            p[#p + 1] = '{"question": "pregunta breve", "options": ["opción corta", "otra opción"]}'
            p[#p + 1] = "Cada opción: 3 palabras como máximo. Entre 2 y 4 opciones. Una sola pregunta."
        end
        p[#p + 1] = "No pongas comillas, viñetas ni explicaciones dentro de los valores."
    else
        p[#p + 1] = "Rewrite the idea delimited by <idea> as ONE clear, concise sentence in English."
        if opts.context and opts.context ~= "" then
            p[#p + 1] = "Project context: " .. opts.context
        end
        for _, qa in ipairs(opts.answers or {}) do
            p[#p + 1] = "You already asked: " .. qa.question .. " The author answered: " .. qa.answer
        end
        if opts.avoid and opts.avoid ~= "" then
            p[#p + 1] = "Propose a clearly different version from this one: " .. opts.avoid
        end
        p[#p + 1] = "Reply with a JSON object ONLY, no extra text and no code fences."
        if opts.no_questions then
            p[#p + 1] = 'Required format: {"idea": "the rewritten sentence"}. Do not ask questions.'
        else
            p[#p + 1] = 'Normal format: {"idea": "the rewritten sentence"}.'
            p[#p + 1] = "Prefer rewriting. Only if the idea is impossible to interpret, reply:"
            p[#p + 1] = '{"question": "short question", "options": ["short option", "another option"]}'
            p[#p + 1] = "Each option: 3 words maximum. Between 2 and 4 options. One question only."
        end
        p[#p + 1] = "Do not put quotes, bullets or explanations inside the values."
    end
    p[#p + 1] = "<idea>" .. idea_text .. "</idea>"
    return table.concat(p, "\n")
end

--- Improve a single idea sentence.
--- `opts` may carry { context, answers = {{question, answer}}, avoid, no_questions }.
--- On success the callback receives a table:
---   { kind = "idea",     text = "..." }
---   { kind = "question", question = "...", options = { "...", ... } }
--- A reply that is neither valid JSON nor a usable question degrades to `idea`
--- with the sanitized text, which the caller screens with looks_like_question.
function M.improve_idea(idea_text, lang, callback, opts)
    opts = opts or {}
    M.generate_text(build_improve_prompt(idea_text, lang, opts), function(raw, err)
        if err or not raw then
            callback(nil, err)
            return
        end
        local data = extract_json(raw)
        if data then
            if type(data.question) == "string" and data.question ~= "" then
                local options = normalize_options(data.options)
                if options then
                    callback({
                        kind = "question",
                        question = M.to_single_line(data.question),
                        options = options,
                    })
                    return
                end
            end
            -- Structured reply we cannot use: a question with no pickable
            -- options, or neither field. Reporting it beats storing raw JSON.
            if type(data.idea) ~= "string" or data.idea == "" then
                callback({ kind = "unusable" })
                return
            end
        end
        local text = M.to_single_line(data and data.idea or raw)
        if text == "" then
            callback(nil, "empty response")
            return
        end
        callback({ kind = "idea", text = text })
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
