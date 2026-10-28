-- llm.lua, minus the transport. The curl call itself is not exercised: what
-- matters here is the prompt that goes out and the stripping that happens to
-- whatever comes back, because a heading the model invents would become
-- structure in the export.
local helpers = require("tests.helpers")
local llm = require("wyt.llm")
local types = require("wyt.types")

describe("llm.to_single_line", function()
    it("strips a list index but keeps a year", function()
        assert.equals("The Silence of Cities", llm.to_single_line("1. The Silence of Cities"))
        assert.equals("1984. The Year", llm.to_single_line("1984. The Year"))
    end)

    it("takes the first line that says something", function()
        assert.equals("The real answer", llm.to_single_line("\n\n  \nThe real answer\nmore"))
    end)

    it("strips a list marker", function()
        assert.equals("An idea", llm.to_single_line("- An idea"))
        assert.equals("An idea", llm.to_single_line("* An idea"))
        assert.equals("An idea", llm.to_single_line("1. An idea"))
    end)

    it("strips a heading marker", function()
        assert.equals("A title", llm.to_single_line("## A title"))
    end)

    it("unwraps surrounding quotes, which models add to names", function()
        assert.equals("The Silence of Cities", llm.to_single_line('"The Silence of Cities"'))
    end)

    it("keeps a quotation that is part of the sentence", function()
        local titled = "Ella relee " .. string.char(0xC2, 0xAB) .. "Rayuela" .. string.char(0xC2, 0xBB)
        assert.equals(titled, llm.to_single_line(titled))
    end)

    it("returns empty for a reply with nothing in it", function()
        assert.equals("", llm.to_single_line(""))
        assert.equals("", llm.to_single_line("\n\n   \n"))
    end)
end)

describe("llm.to_prose", function()
    it("drops a heading the model invented", function()
        local out = llm.to_prose("# Chapter One\n\nThe street was empty.")
        assert.has_no_match("#", out)
        assert.matches("The street was empty%.", out)
    end)

    it("drops code fences", function()
        assert.has_no_match("```", llm.to_prose("```\nThe street was empty.\n```"))
    end)

    it("drops list markers but keeps the text", function()
        -- Exact: a pattern anchored at ^ only ever looked at the first line.
        assert.equals("first point\nsecond point", llm.to_prose("- first point\n- second point"))
    end)

    it("leaves plain prose alone", function()
        assert.equals("The street was empty.", llm.to_prose("The street was empty."))
    end)
end)

describe("llm.looks_like_question", function()
    it("spots a reply that is a question rather than a name", function()
        assert.truthy(llm.looks_like_question("What should this chapter be called?"))
    end)

    it("accepts a real name", function()
        assert.falsy(llm.looks_like_question("The empty platform"))
    end)

    -- The opener is two bytes, so it is matched whole: inside a `[...]` class it
    -- would eat the 0xC2 off every Spanish question instead.
    it("spots a Spanish question by either mark", function()
        local opener = string.char(0xC2, 0xBF)
        assert.truthy(llm.looks_like_question(opener .. "De qui" .. string.char(0xC3, 0xA9) .. "n es la idea"))
        assert.truthy(llm.looks_like_question("De qui" .. string.char(0xC3, 0xA9) .. "n es la idea?"))
    end)
end)

describe("llm.generate_in_context", function()
    local captured, restore

    before_each(function()
        if restore then restore() end
        captured, restore = helpers.capture_prompt("")
    end)

    local function prompt_for(ctx)
        llm.generate_in_context(ctx, function() end)
        return captured.prompt
    end

    it("asks for a bridge when the cursor sits between two paragraphs", function()
        local p = prompt_for({
            mode = "text", lang = "en", project = "Novel. A city that forgets.",
            prose_kind = types.prose_kind("novel", "en"),
            heading = "The platform", before = "Before.", after = "After.",
        })
        assert.matches("The text just before the cursor: Before%.", p)
        assert.matches("The text just after the cursor: After%.", p)
        assert.matches("carries the reader from what comes before", p)
        assert.matches("a narrative paragraph", p)
    end)

    it("asks for a continuation when nothing follows the cursor", function()
        local p = prompt_for({
            mode = "text", lang = "en", project = "Essay.",
            prose_kind = types.prose_kind("essay", "en"), before = "Before.",
        })
        assert.matches("an argumentative paragraph that comes next", p)
        assert.has_no_match("carries the reader", p)
    end)

    it("asks each type for its own kind of paragraph", function()
        local function kind_line(type_name, lang)
            return prompt_for({
                mode = "text", lang = lang, project = "x",
                prose_kind = types.prose_kind(type_name, lang), before = "Antes.",
            })
        end
        assert.matches("un párrafo narrativo", kind_line("novel", "es"))
        assert.matches("un párrafo de notas conciso", kind_line("summary", "es"))
        assert.matches("un párrafo literario", kind_line("short_story", "es"))
    end)

    it("still reads when the caller omits the paragraph kind", function()
        local p = prompt_for({ mode = "text", lang = "es", project = "x", before = "Antes." })
        assert.matches("Escribe un párrafo que siga a lo anterior%.", p)
    end)

    it("asks for ideas, not prose, inside a plan", function()
        local p = prompt_for({
            mode = "plan", lang = "en", project = "Novel.",
            prose_kind = types.prose_kind("novel", "en"),
            heading = "Chapter one", existing = "a; b", max_ideas = 5,
        })
        assert.matches("Ideas already listed here: a; b", p)
        assert.matches("do not repeat the ones already listed", p)
        assert.matches("at most 5 ideas", p)
        assert.has_no_match("narrative paragraph", p)
    end)

    it("lets an explicit instruction replace the positional task", function()
        local p = prompt_for({
            mode = "text", lang = "en", project = "Novel.",
            prose_kind = types.prose_kind("novel", "en"),
            before = "Before.", after = "After.", instruction = "Make it rain.",
        })
        assert.matches("Make it rain%.", p)
        assert.has_no_match("carries the reader", p)
    end)

    it("omits the parts the cursor does not have", function()
        local p = prompt_for({ mode = "text", lang = "en", project = "Novel." })
        assert.has_no_match("The cursor is inside", p)
        assert.has_no_match("just before the cursor", p)
        assert.has_no_match("just after the cursor", p)
    end)

    it("always forbids markdown in prose mode", function()
        local p = prompt_for({ mode = "text", lang = "en", project = "Novel.", before = "B." })
        assert.matches("no headings", p)
    end)

    it("writes the whole prompt in the project's language", function()
        local p = prompt_for({
            mode = "text", lang = "es", project = "Novela.",
            prose_kind = types.prose_kind("novel", "es"), before = "Antes.",
        })
        assert.matches("Proyecto:", p)
        assert.has_no_match("Project:", p)
    end)

    it("falls back to English for a language it has no wording for", function()
        local p = prompt_for({ mode = "text", lang = "de", project = "Novel.", before = "B." })
        assert.matches("Project:", p)
    end)
end)

describe("llm.expand_idea", function()
    local captured, restore

    before_each(function()
        if restore then restore() end
        captured, restore = helpers.capture_prompt("A paragraph.")
    end)

    local function prompt_for(idea, context, lang, opts)
        llm.expand_idea(idea, context, lang, function() end, opts)
        return captured.prompt
    end

    it("asks for the type's paragraph, not a generic literary one", function()
        local p = prompt_for("Density is a choice", "Essay. On urban space.", "en",
            { prose_kind = types.prose_kind("essay", "en") })
        assert.matches("Write an argumentative paragraph based on the idea below%.", p)
    end)

    it("tells a summary to merge the points its placeholder carries", function()
        local p = prompt_for("a; b; c", "Resumen.", "es",
            { prose_kind = types.prose_kind("summary", "es"), merge = true })
        assert.matches("separados por ';'", p)
        assert.matches("un solo párrafo", p)
    end)

    it("says nothing about merging for a type that does not", function()
        local p = prompt_for("Llega el tren", "Novela.", "es",
            { prose_kind = types.prose_kind("novel", "es"), merge = false })
        assert.has_no_match("separados por", p)
    end)

    it("passes the project frame through", function()
        local p = prompt_for("Llega el tren", "Novela. Una ciudad que olvida. El andén", "es", {})
        assert.matches("Contexto del proyecto: Novela%. Una ciudad que olvida%. El andén", p)
    end)

    it("omits the context line when there is no context", function()
        assert.has_no_match("Project context", prompt_for("An idea", "", "en", {}))
        assert.has_no_match("Project context", prompt_for("An idea", nil, "en", {}))
    end)

    it("puts each part on its own line, so no period is ever doubled", function()
        local p = prompt_for("An idea", "Essay. On urban space.", "en",
            { prose_kind = types.prose_kind("essay", "en"), merge = true })
        assert.has_no_match("%.%.", p)
    end)

    it("works with no opts at all, for a caller that has none", function()
        local p = prompt_for("Idea suelta", "", "es", nil)
        assert.matches("Escribe un párrafo literario", p)
    end)

    it("strips the reply, because a heading would become export structure", function()
        restore()
        captured, restore = helpers.capture_prompt("# Invented\n\nThe street was empty.")
        local result
        llm.expand_idea("An idea", "", "en", function(r) result = r end, {})
        assert.has_no_match("#", result)
        assert.matches("The street was empty%.", result)
    end)

    it("reports an error instead of inserting it", function()
        restore()
        local original = llm.generate_text
        llm.generate_text = function(_, callback) callback(nil, "no api key") end
        local result, err
        llm.expand_idea("An idea", "", "en", function(r, e) result, err = r, e end, {})
        llm.generate_text = original
        captured, restore = helpers.capture_prompt("")
        assert.is_nil(result)
        assert.equals("no api key", err)
    end)
end)

describe("llm.suggest_group_name", function()
    local captured, restore

    before_each(function()
        if restore then restore() end
        captured, restore = helpers.capture_prompt("The empty platform")
    end)

    it("gives the type on its own line, so no article has to agree with it", function()
        llm.suggest_group_name({ "una", "otra" }, types.label("long_novel", "es"), "es", function() end)
        assert.matches("Tipo de texto: Novela larga", captured.prompt)
        assert.has_no_match("de un Novela", captured.prompt)
    end)

    it("never sends the raw id", function()
        llm.suggest_group_name({ "a" }, types.label("short_story", "en"), "en", function() end)
        assert.has_no_match("short_story", captured.prompt)
        assert.matches("Text type: Short story", captured.prompt)
    end)

    it("lists every idea it was given", function()
        llm.suggest_group_name({ "first", "second" }, "Essay", "en", function() end)
        assert.matches("%- first", captured.prompt)
        assert.matches("%- second", captured.prompt)
    end)

    it("reduces the reply to one line", function()
        restore()
        captured, restore = helpers.capture_prompt('"The empty platform"\nand more')
        local name
        llm.suggest_group_name({ "a" }, "Essay", "en", function(n) name = n end)
        assert.equals("The empty platform", name)
    end)
end)

describe("llm.improve_idea", function()
    local restore

    local function answer(reply, opts)
        if restore then restore() end
        local _, r = helpers.capture_prompt(reply)
        restore = r
        local result, err
        llm.improve_idea("vague idea", "en", function(res, e) result, err = res, e end, opts or {})
        return result, err
    end

    it("refuses a question once questions are off, however the model replies", function()
        local reply = '{"question": "Which city?", "options": ["Bogota", "Lima"]}'
        assert.equals("unusable", answer(reply, { no_questions = true }).kind)
        local both = '{"question": "Which city?", "options": ["Bogota"], "idea": "A clear sentence."}'
        assert.equals("A clear sentence.", answer(both, { no_questions = true }).text)
    end)

    it("returns the rewritten sentence from a JSON reply", function()
        local result = answer('{"idea": "A clear sentence."}')
        assert.equals("idea", result.kind)
        assert.equals("A clear sentence.", result.text)
    end)

    it("returns a question the model asked, with its options", function()
        local result = answer('{"question": "Which city?", "options": ["Bogota", "Lima"]}')
        assert.equals("question", result.kind)
        assert.equals("Which city?", result.question)
        assert.same({ "Bogota", "Lima" }, result.options)
    end)

    it("rejects a question with nothing to pick from", function()
        assert.equals("unusable", answer('{"question": "Which city?", "options": ["only one"]}').kind)
    end)

    it("rejects a structured reply with neither field", function()
        assert.equals("unusable", answer('{"unrelated": "x"}').kind)
    end)

    it("rejects broken JSON rather than storing its braces", function()
        assert.equals("unusable", answer('{"idea": "unterminated').kind)
    end)

    it("accepts plain prose as the idea, since that is what it asked for", function()
        local result = answer("A clear sentence.")
        assert.equals("idea", result.kind)
        assert.equals("A clear sentence.", result.text)
    end)

    it("passes the error up instead of inventing an idea", function()
        if restore then restore() end
        local original = llm.generate_text
        llm.generate_text = function(_, callback) callback(nil, "network down") end
        local result, err
        llm.improve_idea("vague", "en", function(res, e) result, err = res, e end, {})
        llm.generate_text = original
        assert.is_nil(result)
        assert.equals("network down", err)
    end)
end)

describe("llm.today", function()
    it("asks for a prompt only when the writer was away under a day", function()
        local captured = helpers.capture_prompt('{"prompt": "What does the harbour master want?"}')
        local got
        require("wyt.llm").today({ lang = "en", depth = "paragraph", text = "SCENE", last_paragraph = "LAST" },
            function(r) got = r end)
        assert.has_no_match("SCENE", captured.prompt)
        assert.matches("LAST", captured.prompt)
        assert.has_no_match('"summary"', captured.prompt)
        assert.equals("What does the harbour master want?", got.prompt)
        assert.is_nil(got.summary)
    end)

    it("sends the scene and asks for its summary after a few days", function()
        local captured = helpers.capture_prompt('```json\n{"summary": "- She arrives.", "prompt": "Who meets her?"}\n```')
        local got
        require("wyt.llm").today({ lang = "es", depth = "scene", text = "ESCENA", last_paragraph = "ULTIMO" },
            function(r) got = r end)
        assert.matches("La escena que estaba escribiendo", captured.prompt)
        assert.matches("ESCENA", captured.prompt)
        -- Markdown the model wraps it in never reaches the brief.
        assert.equals("She arrives.", got.summary)
        assert.equals("Who meets her?", got.prompt)
    end)

    it("keeps a reply that skipped the JSON as the prompt", function()
        helpers.capture_prompt("Who is waiting on the pier?")
        local got
        require("wyt.llm").today({ lang = "en", depth = "chapter", text = "x" }, function(r) got = r end)
        assert.equals("Who is waiting on the pier?", got.prompt)
        assert.is_nil(got.summary)
    end)

    it("keeps the end of a chapter over the budget", function()
        local captured = helpers.capture_prompt('{"prompt": "Go on."}')
        local chapter = "START " .. ("ñ"):rep(8000)
        require("wyt.llm").today({ lang = "en", depth = "chapter", text = chapter }, function() end)
        assert.falsy(captured.prompt:find("START", 1, true))
        assert.truthy(captured.prompt:find(("ñ"):rep(8000), 1, true))
    end)

    it("drops a reply that tried JSON and broke it", function()
        helpers.capture_prompt('{"summary": "She arrives.", "prompt": "Who')
        local got
        require("wyt.llm").today({ lang = "en", depth = "chapter", text = "x" }, function(r) got = r end)
        assert.is_nil(got.prompt)
        assert.is_nil(got.summary)
    end)
end)

describe("llm.place", function()
    local ctx = {
        lang = "es",
        paragraphs = { { n = 1, text = "La puerta." } },
        targets = { { id = "T1", label = "Idea nueva en: Puerto" } },
        change = { previous = "Idea en: Puerto", note = "es la huelga" },
    }

    it("asks in the project's language, with the writer's note", function()
        local captured = helpers.capture_prompt('{"chunks": []}')
        require("wyt.llm").place(ctx, function() end)
        assert.matches("Un autor escribió estos párrafos", captured.prompt)
        assert.truthy(captured.prompt:find("[1] La puerta.", 1, true))
        assert.truthy(captured.prompt:find("T1: Idea nueva en: Puerto", 1, true))
        assert.truthy(captured.prompt:find("es la huelga", 1, true))
    end)

    it("keeps each chunk's names to one clean line, and drops malformed chunks", function()
        helpers.capture_prompt('```json\n{"chunks": [{"paragraphs": [1], "target": "T1", "idea": "## la puerta\\nencadenada", "why": ""},'
            .. ' {"target": "T1"}, "x"]}\n```')
        local got
        require("wyt.llm").place(ctx, function(r) got = r end)
        assert.equals(1, #got)
        -- The first line only, undecorated: it becomes a plan line or a slug.
        assert.equals("la puerta", got[1].idea)
        assert.is_nil(got[1].why)
    end)

    it("is an error when the reply has no chunks", function()
        helpers.capture_prompt("I would put it in the harbour.")
        local got, err = false, nil
        require("wyt.llm").place(ctx, function(r, e) got, err = r, e end)
        assert.is_nil(got)
        assert.truthy(err)
    end)
end)

describe("a heading marker never survives into a name", function()
    it("is stripped from a single line, as it is from prose", function()
        assert.equals("A title", llm.to_single_line("## A title"))
        assert.equals("A title", llm.to_single_line("# A title"))
    end)

    it("leaves a hashtag alone, since it has no space after the hash", function()
        assert.equals("#silence", llm.to_single_line("#silence"))
    end)
end)

describe("llm.generate_text with a PDF", function()
    local config = require("wyt.config")

    -- The request body each provider would have been sent, read back from the
    -- curl config on stdin. The transport is stubbed, so nothing goes out.
    local function body_for(provider)
        local options, system = config.options, vim.system
        config.setup({ llm_provider = provider, api_key = "test-key" })
        local stdin
        vim.system = function(_, o) stdin = o.stdin; return {} end
        llm.generate_text("read this", function() end, { pdf = "UERG", max_tokens = 8192 })
        vim.system = system
        config.options = options
        config.setup({})
        local quoted = stdin:match('data%-binary = "(.-)"\r?\n$')
        return vim.json.decode((quoted:gsub("\\(.)", "%1")))
    end

    it("sends Claude the PDF as a document block, before the prompt", function()
        local body = body_for("claude")
        assert.equals(8192, body.max_tokens)
        local content = body.messages[1].content
        assert.same({ type = "base64", media_type = "application/pdf", data = "UERG" }, content[1].source)
        assert.same({ type = "text", text = "read this" }, content[2])
    end)

    it("sends OpenAI the PDF as a file part, before the prompt", function()
        local body = body_for("openai")
        local content = body.messages[1].content
        assert.equals("data:application/pdf;base64,UERG", content[1].file.file_data)
        assert.same({ type = "text", text = "read this" }, content[2])
    end)
end)

describe("llm.generate_text cut off at the token limit", function()
    local config = require("wyt.config")

    -- What the caller gets for a reply `body`. The transport is stubbed.
    local function reply_for(provider, body)
        local options, system = config.options, vim.system
        config.setup({ llm_provider = provider, api_key = "test-key" })
        vim.system = function(_, _, on_exit)
            on_exit({ code = 0, stdout = vim.json.encode(body), stderr = "" })
            return {}
        end
        local got, err, done
        llm.generate_text("write", function(text, e) got, err, done = text, e, true end)
        vim.system = system
        config.options = options
        config.setup({})
        vim.wait(1000, function() return done end)
        return got, err
    end

    it("is an error from Claude, not a shorter reply", function()
        local text, err = reply_for("claude", { stop_reason = "max_tokens", content = { { type = "text", text = "half a" } } })
        assert.is_nil(text)
        assert.matches("cut off", err)
    end)

    it("is an error from OpenAI, not a shorter reply", function()
        local text, err = reply_for("openai", { choices = { { finish_reason = "length", message = { content = "half a" } } } })
        assert.is_nil(text)
        assert.matches("cut off", err)
    end)
end)
