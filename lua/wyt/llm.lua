-- P1: real async LLM calls via curl (vim.system)
-- All public functions are async: they accept a callback(result, err)
local M = {}

local function get_opts()
    local config = require("wyt.config")
    return config.options.llm_provider, config.options.api_key
end

-- Internal: call OpenAI chat completions endpoint
local function call_openai(prompt, api_key, callback)
    local body = vim.json.encode({
        model = "gpt-4o",
        messages = { { role = "user", content = prompt } },
        max_tokens = 1024,
    })
    vim.system({
        "curl", "-s", "-X", "POST",
        "https://api.openai.com/v1/chat/completions",
        "-H", "Content-Type: application/json",
        "-H", "Authorization: Bearer " .. api_key,
        "-d", body,
    }, { text = true }, function(result)
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
                callback(nil, data.error.message or vim.inspect(data.error))
                return
            end
            local text = data.choices
                and data.choices[1]
                and data.choices[1].message
                and data.choices[1].message.content
            callback(text or "", nil)
        end)
    end)
end

-- Internal: call Anthropic Messages endpoint
local function call_claude(prompt, api_key, callback)
    local body = vim.json.encode({
        model = "claude-opus-4-6",
        max_tokens = 1024,
        messages = { { role = "user", content = prompt } },
    })
    vim.system({
        "curl", "-s", "-X", "POST",
        "https://api.anthropic.com/v1/messages",
        "-H", "Content-Type: application/json",
        "-H", "x-api-key: " .. api_key,
        "-H", "anthropic-version: 2023-06-01",
        "-d", body,
    }, { text = true }, function(result)
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
                callback(nil, (data.error.type or "") .. ": " .. (data.error.message or vim.inspect(data.error)))
                return
            end
            local text = data.content and data.content[1] and data.content[1].text
            callback(text or "", nil)
        end)
    end)
end

-- Public async API: callback(result_string, err_string_or_nil)
function M.generate_text(prompt, callback)
    local provider, api_key = get_opts()

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

-- Convenience wrapper: improve a single idea sentence
function M.improve_idea(idea_text, lang, callback)
    local prompt = lang == "es"
        and ("Reescribe la siguiente idea como una oración clara y concisa para un proyecto literario: " .. idea_text)
        or  ("Rewrite the following idea as a single clear, concise sentence for a literary project: " .. idea_text)
    M.generate_text(prompt, callback)
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
            .. "\nResponde solo con el nombre del grupo, sin explicación."
    else
        prompt = "Suggest a short, descriptive name for a group of ideas in a " .. type_name
            .. ".\nIdeas:\n- " .. ideas_str
            .. "\nReply with only the group name, no explanation."
    end
    M.generate_text(prompt, callback)
end

return M
