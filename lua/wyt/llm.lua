-- P1: real async LLM calls via curl (vim.system)
-- All public functions are async: they accept a callback(result, err)
local M = {}

local NL = string.char(10)

local function get_opts()
    local config = require("wyt.config")
    local key, err = config.get_api_key()
    return config.options.llm_provider, key, err
end

-- Quote a value for curl's config-file syntax. A raw newline ends the line and
-- turns what follows into another curl option, and the header line carries the
-- API key: a newline pasted in with a key would otherwise be able to write a
-- file or change the URL. curl reads these escapes back inside a quoted value.
local function curl_quote(s)
    local escaped = s:gsub("\\", "\\\\"):gsub('"', '\\"')
        :gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
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

    -- -sS: quiet, but still report why a request failed. Under -s alone the
    -- stderr this reads back is always empty, so the error had no detail at all.
    local cmd = { "curl", "-sS", "--config", "-" }
    local stdin = table.concat(lines, NL) .. NL
    -- vim.system throws when curl is not installed, which would leave the
    -- caller's callback hanging forever.
    local ok, err = pcall(vim.system, cmd, { text = true, stdin = stdin }, callback)
    if not ok then
        -- `callback` reads a finished process, so hand it one that failed: the
        -- writer gets the reason, not a stack trace from the response handler.
        vim.schedule(function()
            callback({ code = -1, stdout = "", stderr = "curl could not be run: " .. tostring(err) })
        end)
    end
end

-- Shared response handling for both providers.
-- `extract` pulls the assistant text out of a decoded, error-free payload.
local function handle_response(result, callback, extract)
    vim.schedule(function()
        if result.code ~= 0 then
            local detail = result.stderr ~= nil and result.stderr ~= "" and result.stderr
                or ("exit " .. result.code)
            callback(nil, "curl error: " .. detail)
            return
        end
        local ok, data = pcall(vim.json.decode, result.stdout)
        if not ok then
            callback(nil, "JSON parse error: " .. tostring(data))
            return
        end
        -- A body that is not an object (null, a bare number) has no fields to read.
        if type(data) ~= "table" then
            callback(nil, "unexpected response: " .. tostring(result.stdout):sub(1, 200))
            return
        end
        if data.error then
            local message = data.error.message or vim.inspect(data.error)
            callback(nil, data.error.type and (data.error.type .. ": " .. message) or message)
            return
        end
        -- A JSON null decodes to vim.NIL, which is truthy: a refusal with
        -- "content": null used to reach the callback as userdata and blow up in
        -- the first gsub, leaving the rest of a batch unfinished.
        local text = extract(data)
        callback(type(text) == "string" and text or "", nil)
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

-- Only a matched pair comes off. Stripping each side on its own turned
-- `Ella relee <<Rayuela>>` into a sentence missing its closing mark, and that
-- text becomes an idea, a group name, and a folder slug.
local function strip_wrapping_quotes(s)
    local changed = true
    while changed do
        changed = false
        for i, open_q in ipairs(OPEN_QUOTES) do
            local close_q = CLOSE_QUOTES[i]
            if #s > #open_q + #close_q
                and s:sub(1, #open_q) == open_q
                and s:sub(-#close_q) == close_q
            then
                s = s:sub(#open_q + 1, #s - #close_q)
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
    -- A heading marker, by the same rule to_prose uses: `#` then whitespace. A
    -- name is never a heading, and a group called "## The platform" would carry
    -- the hashes into its folder slug and its `## Group:` line. `#silence` with
    -- no space is a hashtag the writer may have wanted, so it stays.
    line = line:gsub("^#+%s+", "")
    -- Two digits at most: a model numbering its answers never reaches a hundred,
    -- while "1984. " opening a title or a paragraph is a year the writer meant.
    line = line:gsub("^%d%d?[%.%)]%s+", "")     -- "1. " / "1) "
    line = line:gsub("^%*%*(.-)%*%*$", "%1")    -- **bold**
    line = line:gsub("^%*(.-)%*$", "%1")        -- *italic*
    return vim.trim(strip_wrapping_quotes(line))
end

--- Collapse an LLM reply to the single clean line the caller can store.
function M.to_single_line(text)
    if not text or text == "" then return "" end
    return (strip_decoration(first_meaningful_line(text)):gsub("%s+", " "))
end

--- Strip the structure a model wraps prose in: code fences, headings, list
--- markers. Generated text lands in `text.wyt.md`, where a heading is not
--- decoration: WYT reads `##` lines as group markers and the export builds the
--- document outline from them, so a title the model invented shows up as a
--- section of the finished text. Paragraph breaks are kept.
function M.to_prose(text)
    if not text or text == "" then return "" end
    text = text:gsub("```%w*", ""):gsub("```", "")
    -- A heading is one or more `#` followed by a space or nothing. `#silence`
    -- with no space is a hashtag the writer may well have wanted.
    local function is_heading(line)
        return line:match("^%s*#+%s") ~= nil or line:match("^%s*#+%s*$") ~= nil
    end
    local kept = {}
    for _, line in ipairs(vim.split(text, "\n", { plain = true })) do
        if not is_heading(line) then
            line = line:gsub("^%s*[%-%*%+]%s+", "")
            line = line:gsub("^%s*%d%d?[%.%)]%s+", "")
            kept[#kept + 1] = line
        end
    end
    local prose = table.concat(kept, "\n"):gsub("\n\n\n+", "\n\n")
    return vim.trim(prose)
end

--- True when a reply is a clarifying question rather than the answer. The model
--- has no one to ask, so the caller keeps the user's own text instead.
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
            -- Once questions are off, a question is refused here rather than
            -- trusted to the prompt: a model that keeps asking would otherwise
            -- loop for as long as the writer keeps skipping.
            if not opts.no_questions and type(data.question) == "string" and data.question ~= "" then
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
        -- A reply that opens like JSON but does not parse is a broken
        -- structured answer, not prose; storing its braces would be worse
        -- than reporting it.
        if not data and vim.trim(raw):sub(1, 1) == "{" then
            callback({ kind = "unusable" })
            return
        end
        local text = M.to_single_line(data and data.idea or raw)
        if text == "" then
            callback(nil, "empty response")
            return
        end
        callback({ kind = "idea", text = text })
    end)
end

-- What the model is told, per language. Only the parts the cursor actually has
-- are used: a paragraph with nothing after it asks for a continuation, one
-- between two others asks for a bridge. `connector` and `continue` take the
-- kind of paragraph the project's type wants, so an essay is not asked for the
-- same thing as a novel; `kind` is the fallback for a caller that omits it.
local CONTEXT_PROMPT = {
    en = {
        frame = "Project: %s",
        about = "The project is about: %s",
        under = "The cursor is inside: %s",
        before = "The text just before the cursor: %s",
        after = "The text just after the cursor: %s",
        existing = "Ideas already listed here: %s",
        kind = "a paragraph",
        connector = "Write %s that carries the reader from what comes before to what comes after.",
        continue = "Write %s that comes next.",
        brainstorm = "Propose new ideas that belong here and do not repeat the ones already listed.",
        prose_only = "Reply with the prose only: no title, no headings, no lists, no other markdown.",
        ideas_only = "Reply with at most %d ideas, one per line, each a single sentence."
            .. " No bullets, no numbering, no explanation.",
    },
    es = {
        frame = "Proyecto: %s",
        about = "El proyecto trata de: %s",
        under = "El cursor está dentro de: %s",
        before = "El texto justo antes del cursor: %s",
        after = "El texto justo después del cursor: %s",
        existing = "Ideas que ya están aquí: %s",
        kind = "un párrafo",
        connector = "Escribe %s que lleve al lector de lo anterior a lo siguiente.",
        continue = "Escribe %s que siga a lo anterior.",
        brainstorm = "Propón ideas nuevas que encajen aquí y que no repitan las que ya están.",
        prose_only = "Responde solo con la prosa: sin título, sin encabezados, sin listas"
            .. " y sin ningún otro formato markdown.",
        ideas_only = "Responde con %d ideas como máximo, una por línea, cada una en una sola frase."
            .. " Sin viñetas, sin numeración y sin explicación.",
    },
}

--- Generate for what surrounds the cursor. `ctx` is built by `wyt.generate`:
--- where the cursor is, what is around it, and what the writer asked for.
--- The instruction is optional; without one the position decides the task.
function M.generate_in_context(ctx, callback)
    local words = CONTEXT_PROMPT[ctx.lang] or CONTEXT_PROMPT.en
    local parts = {}
    local function add(template, value)
        if value and value ~= "" then parts[#parts + 1] = template:format(value) end
    end

    add(words.frame, ctx.project)
    add(words.under, ctx.heading)
    add(words.before, ctx.before)
    add(words.after, ctx.after)
    add(words.existing, ctx.existing)

    local kind = ctx.prose_kind or words.kind
    if ctx.instruction and ctx.instruction ~= "" then
        parts[#parts + 1] = ctx.instruction
    elseif ctx.mode == "plan" then
        parts[#parts + 1] = words.brainstorm
    elseif ctx.before and ctx.after then
        parts[#parts + 1] = words.connector:format(kind)
    else
        parts[#parts + 1] = words.continue:format(kind)
    end

    if ctx.mode == "plan" then
        parts[#parts + 1] = words.ideas_only:format(ctx.max_ideas or 5)
    else
        parts[#parts + 1] = words.prose_only
    end

    M.generate_text(table.concat(parts, "\n"), callback)
end

-- One line each, like CONTEXT_PROMPT. Gluing these together with ". " instead
-- doubled the period whenever a part already ended in one.
local EXPAND_PROMPT = {
    en = {
        kind = "a literary paragraph",
        write = "Write %s based on the idea below.",
        context = "Project context: %s",
        idea = "Idea: %s",
        merge = "The idea carries several points separated by ';':"
            .. " merge all of them into a single paragraph.",
        prose_only = "Reply with the prose only: no title, no headings, no lists,"
            .. " no other markdown formatting.",
    },
    es = {
        kind = "un párrafo literario",
        write = "Escribe %s sobre la idea de abajo.",
        context = "Contexto del proyecto: %s",
        idea = "Idea: %s",
        merge = "La idea trae varios puntos separados por ';':"
            .. " fúndelos todos en un solo párrafo.",
        prose_only = "Responde solo con la prosa: sin título, sin encabezados,"
            .. " sin listas y sin ningún otro formato markdown.",
    },
}

--- Generate a paragraph from an idea.
--- `opts` may carry { prose_kind, merge }: the kind of paragraph the project's
--- type wants, and whether the idea is really several ideas that have to be
--- folded into one paragraph, which is what a summary's placeholder holds.
function M.expand_idea(idea_text, context, lang, callback, opts)
    opts = opts or {}
    local words = EXPAND_PROMPT[lang] or EXPAND_PROMPT.en
    local parts = { words.write:format(opts.prose_kind or words.kind) }
    if context and context ~= "" then
        parts[#parts + 1] = words.context:format(context)
    end
    parts[#parts + 1] = words.idea:format(idea_text)
    if opts.merge then parts[#parts + 1] = words.merge end
    parts[#parts + 1] = words.prose_only
    local prompt = table.concat(parts, "\n")
    -- The instruction is not enough on its own; the reply is stripped as well,
    -- because one invented title corrupts the export's outline.
    M.generate_text(prompt, function(result, err)
        if err or not result then
            callback(nil, err)
            return
        end
        callback(M.to_prose(result), nil)
    end)
end

--- Suggest a group name from a list of ideas. `type_label` is the type's name
--- in the writer's language, given on its own line: inlined after an article it
--- read as "un grupo de ideas de un Novela larga", which does not agree.
function M.suggest_group_name(ideas, type_label, lang, callback)
    local ideas_str = table.concat(ideas, "\n- ")
    local prompt
    if lang == "es" then
        prompt = "Tipo de texto: " .. type_label
            .. "\nSugiere un nombre corto y descriptivo para este grupo de ideas."
            .. "\nIdeas:\n- " .. ideas_str
            .. "\nResponde solo con el nombre, en una sola línea, sin comillas, sin prefijos"
            .. " como \"Nombre:\" y sin explicación."
    else
        prompt = "Text type: " .. type_label
            .. "\nSuggest a short, descriptive name for this group of ideas."
            .. "\nIdeas:\n- " .. ideas_str
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

-- The summary is only asked for when the writer has been away long enough to
-- need it; the paragraph is always given word for word by the brief itself,
-- never by the model.
local TODAY_PROMPT = {
    en = {
        frame = "Project: %s",
        away = "The writer last wrote %s and is about to start again.",
        scene = "The scene they were writing:\n<text>\n%s\n</text>",
        chapter = "The chapter they were writing:\n<text>\n%s\n</text>",
        last = "Their last paragraph:\n<paragraph>\n%s\n</paragraph>",
        open = "Still open in the project: %s",
        summary = 'In "summary", recall in at most three sentences what happens in that text,'
            .. " so the writer remembers it without rereading it.",
        prompt = 'In "prompt", ask one short question, or give one invitation, that gets them'
            .. " writing the next part right now. One sentence. Do not write the text for them.",
        with_summary = 'Reply with a JSON object only, no code fences: {"summary": "...", "prompt": "..."}',
        prompt_only = 'Reply with a JSON object only, no code fences: {"prompt": "..."}',
    },
    es = {
        frame = "Proyecto: %s",
        away = "El autor escribió por última vez %s y está por volver a empezar.",
        scene = "La escena que estaba escribiendo:\n<text>\n%s\n</text>",
        chapter = "El capítulo que estaba escribiendo:\n<text>\n%s\n</text>",
        last = "Su último párrafo:\n<paragraph>\n%s\n</paragraph>",
        open = "Pendiente en el proyecto: %s",
        summary = 'En "summary", recuerda en tres frases como máximo qué pasa en ese texto,'
            .. " para que el autor lo recuerde sin releerlo.",
        prompt = 'En "prompt", haz una pregunta breve, o una invitación, que lo ponga a escribir'
            .. " la siguiente parte ahora mismo. Una sola frase. No escribas el texto por él.",
        with_summary = 'Responde solo con un objeto JSON, sin bloques de código: {"summary": "...", "prompt": "..."}',
        prompt_only = 'Responde solo con un objeto JSON, sin bloques de código: {"prompt": "..."}',
    },
}

-- The end of a long chapter is what the writer is coming back to, so a text
-- over the budget keeps its last part. Cut by character, not by byte.
local TODAY_TEXT_BUDGET = 8000

--- The model's half of `:WYTToday`. `ctx` is { lang, project, ago, depth, text,
--- last_paragraph, open }: `depth` is "paragraph", "scene" or "chapter", and
--- `text` is the scene or chapter for the two deeper ones.
--- The callback gets { summary = string|nil, prompt = string|nil }.
function M.today(ctx, callback)
    local words = TODAY_PROMPT[ctx.lang] or TODAY_PROMPT.en
    local parts = {}
    local function add(template, value)
        if value and value ~= "" then parts[#parts + 1] = template:format(value) end
    end
    local wants_summary = ctx.depth ~= "paragraph" and ctx.text and ctx.text ~= ""

    add(words.frame, ctx.project)
    add(words.away, ctx.ago)
    if wants_summary then
        local over = vim.fn.strchars(ctx.text) - TODAY_TEXT_BUDGET
        add(ctx.depth == "chapter" and words.chapter or words.scene,
            over > 0 and vim.fn.strcharpart(ctx.text, over) or ctx.text)
    end
    add(words.last, ctx.last_paragraph)
    add(words.open, ctx.open)
    if wants_summary then parts[#parts + 1] = words.summary end
    parts[#parts + 1] = words.prompt
    parts[#parts + 1] = wants_summary and words.with_summary or words.prompt_only

    M.generate_text(table.concat(parts, "\n"), function(raw, err)
        if err or not raw then
            callback(nil, err)
            return
        end
        local data = extract_json(raw)
        -- A reply that skipped the JSON is still a usable prompt; a summary
        -- cannot be told apart from one, so it is dropped. One that tried JSON
        -- and broke it would head the freewrite file with braces and keys.
        if not data then
            local line = raw:find("{", 1, true) and "" or M.to_single_line(raw)
            callback({ prompt = line ~= "" and line or nil })
            return
        end
        local function clean(v, fn)
            if type(v) ~= "string" then return nil end
            v = fn(v)
            return v ~= "" and v or nil
        end
        callback({
            summary = wants_summary and clean(data.summary, M.to_prose) or nil,
            -- The prompt heads a freewrite file, where a heading would be structure.
            prompt = clean(data.prompt, M.to_single_line),
        })
    end)
end

-- The model is handed numbers and ids, and answers with numbers and ids: the
-- writer's paragraphs never pass through it on their way into a text.
local PLACE_PROMPT = {
    en = {
        frame = "Project: %s",
        paragraphs = "A writer wrote these paragraphs freely, before deciding where they go:\n<paragraphs>\n%s\n</paragraphs>",
        targets = "Places in the project, by id:\n%s",
        task = "Group the paragraphs that belong together into chunks, and give each chunk the one place"
            .. ' where it fits best. Use "keep" for a chunk that fits nowhere yet. Do not rewrite them.'
            .. ' A "New idea in" place needs "idea": a short name for what the chunk is about. A "New group in"'
            .. ' place needs "group", a short name for the new group, and "idea". Prefer a place that exists;'
            .. ' use "Idea in" only for a note, never for prose.',
        change = 'The writer did not want "%s" and says: %s',
        reply = 'Reply with a JSON object only, no code fences: {"chunks": [{"paragraphs": [1, 2], "target": "T3",'
            .. ' "why": "one short sentence", "idea": "only for a new idea or group", "group": "only for a new group"}]}',
    },
    es = {
        frame = "Proyecto: %s",
        paragraphs = "Un autor escribió estos párrafos libremente, antes de decidir dónde van:\n<paragraphs>\n%s\n</paragraphs>",
        targets = "Lugares del proyecto, por id:\n%s",
        task = "Agrupa en fragmentos los párrafos que van juntos, y da a cada fragmento el único lugar"
            .. ' donde mejor encaja. Usa "keep" para un fragmento que aún no encaja en ningún lugar. No los reescribas.'
            .. ' Un lugar "Idea nueva en" necesita "idea": un nombre breve de lo que trata el fragmento. Un lugar'
            .. ' "Grupo nuevo en" necesita "group", un nombre breve para el grupo nuevo, e "idea". Prefiere un lugar'
            .. ' que ya existe; usa "Idea en" solo para una nota, nunca para prosa.',
        change = 'El autor no quiso "%s" y dice: %s',
        reply = 'Responde solo con un objeto JSON, sin bloques de código: {"chunks": [{"paragraphs": [1, 2], "target": "T3",'
            .. ' "why": "una frase breve", "idea": "solo para una idea o un grupo nuevos", "group": "solo para un grupo nuevo"}]}',
    },
}

--- The model's half of `:WYTPlace`. `ctx` is { lang, project, paragraphs, targets,
--- change }: `paragraphs` is { { n, text } }, `targets` is { { id, label } }, and
--- `change`, when the writer asked for one, is { previous = label, note }.
--- The callback gets the chunks as the model gave them, unchecked:
--- { { paragraphs = {n...}, target = id, why, idea, group } }, the last three
--- strings or nil. A name lands in a plan line and a group heading, so it is
--- stripped like any reply that lands in a file.
function M.place(ctx, callback)
    local words = PLACE_PROMPT[ctx.lang] or PLACE_PROMPT.en
    local paragraphs, targets = {}, {}
    for _, p in ipairs(ctx.paragraphs) do paragraphs[#paragraphs + 1] = "[" .. p.n .. "] " .. p.text end
    for _, t in ipairs(ctx.targets) do targets[#targets + 1] = t.id .. ": " .. t.label end
    local parts = {}
    if ctx.project and ctx.project ~= "" then parts[#parts + 1] = words.frame:format(ctx.project) end
    parts[#parts + 1] = words.paragraphs:format(table.concat(paragraphs, "\n\n"))
    parts[#parts + 1] = words.targets:format(table.concat(targets, "\n"))
    parts[#parts + 1] = words.task
    if ctx.change then parts[#parts + 1] = words.change:format(ctx.change.previous, ctx.change.note) end
    parts[#parts + 1] = words.reply

    M.generate_text(table.concat(parts, "\n"), function(raw, err)
        if err or not raw then
            callback(nil, err)
            return
        end
        local data = extract_json(raw)
        if not data or type(data.chunks) ~= "table" then
            callback(nil, "no chunks in the reply")
            return
        end
        local function line(v)
            v = type(v) == "string" and M.to_single_line(v) or ""
            return v ~= "" and v or nil
        end
        local chunks = {}
        for _, c in ipairs(data.chunks) do
            if type(c) == "table" and type(c.paragraphs) == "table" then
                chunks[#chunks + 1] = { paragraphs = c.paragraphs, target = c.target,
                    why = line(c.why), idea = line(c.idea), group = line(c.group) }
            end
        end
        callback(chunks)
    end)
end

-- What the writer keeps about the project, for the two calls that answer from
-- it: the reference sections, then the text the question came from.
local KNOWN_PROMPT = {
    en = { frame = "Project: %s",
        reference = "What the writer keeps as reference:\n<reference>\n%s\n</reference>",
        text = "The text they are writing:\n<text>\n%s\n</text>" },
    es = { frame = "Proyecto: %s",
        reference = "Lo que el autor guarda como referencia:\n<reference>\n%s\n</reference>",
        text = "El texto que está escribiendo:\n<text>\n%s\n</text>" },
}

-- The project, its reference and its text, as Ask and Resolve both open.
local function known(ctx, parts)
    local words = KNOWN_PROMPT[ctx.lang] or KNOWN_PROMPT.en
    if ctx.project and ctx.project ~= "" then parts[#parts + 1] = words.frame:format(ctx.project) end
    if ctx.reference and ctx.reference ~= "" then parts[#parts + 1] = words.reference:format(ctx.reference) end
    if ctx.text and ctx.text ~= "" then parts[#parts + 1] = words.text:format(ctx.text) end
end

local ASK_PROMPT = {
    en = { question = "The writer asks: %s",
        task = "Answer briefly, from the reference and the text first. Say so when they do not say, and"
            .. " then answer from what you know. Plain sentences, no headings or lists." },
    es = { question = "El autor pregunta: %s",
        task = "Responde brevemente, primero desde la referencia y el texto. Dilo cuando no lo dicen, y"
            .. " entonces responde desde lo que sabes. Frases simples, sin títulos ni listas." },
}

--- The model's half of `:WYTAsk`. `ctx` is { lang, project, reference, text,
--- question }. The answer is only shown, never written, but it is read as prose.
function M.ask(ctx, callback)
    local words = ASK_PROMPT[ctx.lang] or ASK_PROMPT.en
    local parts = {}
    known(ctx, parts)
    parts[#parts + 1] = words.question:format(ctx.question)
    parts[#parts + 1] = words.task
    M.generate_text(table.concat(parts, "\n"), function(raw, err)
        if err or not raw then return callback(nil, err) end
        local answer = M.to_prose(raw)
        if answer == "" then return callback(nil, "empty reply") end
        callback(answer)
    end)
end

local RESOLVE_PROMPT = {
    en = { markers = "The writer left these gaps in their text, each a wyt marker with what it needs, by id,"
            .. " and the paragraph it sits in:\n%s",
        task = "For each, write only the words that replace the marker in its paragraph, in the language"
            .. " of the text, so the sentence reads on. Give exactly what the marker asks for, in as few"
            .. " words as the sentence needs (a name, a date, a place), and nothing it does not ask for."
            .. " Take facts from the reference and the text first; otherwise give your best answer."
            .. " Never rewrite the rest of the paragraph.",
        change = 'The writer did not want "%s" and says: %s',
        note = "The writer says: %s",
        reply = 'Reply with a JSON object only, no code fences: {"answers": [{"id": "M1", "text": "..."}]}' },
    es = { markers = "El autor dejó estos huecos en su texto, cada uno una marca wyt con lo que necesita, por id,"
            .. " y el párrafo donde está:\n%s",
        task = "Para cada uno, escribe solo las palabras que reemplazan la marca en su párrafo, en el idioma"
            .. " del texto, de modo que la frase siga. Da exactamente lo que la marca pide, en tan pocas"
            .. " palabras como la frase necesite (un nombre, una fecha, un lugar), y nada que no pida."
            .. " Toma los datos primero de la referencia y del texto; si no, da tu mejor respuesta."
            .. " Nunca reescribas el resto del párrafo.",
        change = 'El autor no quiso "%s" y dice: %s',
        note = "El autor dice: %s",
        reply = 'Responde solo con un objeto JSON, sin bloques de código: {"answers": [{"id": "M1", "text": "..."}]}' },
}

--- The model's half of `:WYTResolve`. `ctx` is { lang, project, reference,
--- markers = { { id, text, paragraph } }, change = { previous?, note } }. The
--- callback gets { [id] = answer }: an answer lands in a text, so it is
--- stripped like any reply that lands in a file.
function M.resolve(ctx, callback)
    local words = RESOLVE_PROMPT[ctx.lang] or RESOLVE_PROMPT.en
    local list = {}
    for _, m in ipairs(ctx.markers) do
        list[#list + 1] = m.id .. ": " .. m.text .. "\n<paragraph>\n" .. (m.paragraph or "") .. "\n</paragraph>"
    end
    local parts = {}
    known(ctx, parts)
    parts[#parts + 1] = words.markers:format(table.concat(list, "\n\n"))
    parts[#parts + 1] = words.task
    -- No previous answer when the first reply had none for this marker.
    if ctx.change and ctx.change.previous then
        parts[#parts + 1] = words.change:format(ctx.change.previous, ctx.change.note)
    elseif ctx.change then
        parts[#parts + 1] = words.note:format(ctx.change.note)
    end
    parts[#parts + 1] = words.reply

    M.generate_text(table.concat(parts, "\n"), function(raw, err)
        if err or not raw then return callback(nil, err) end
        local data = extract_json(raw)
        if not data or type(data.answers) ~= "table" then return callback(nil, "no answers in the reply") end
        local out = {}
        for _, a in ipairs(data.answers) do
            if type(a) == "table" and type(a.id) == "string" and type(a.text) == "string" then
                local text = M.to_prose(a.text)
                if text ~= "" then out[a.id] = text end
            end
        end
        callback(out)
    end)
end

return M
