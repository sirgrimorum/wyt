local config = require("wyt.config")
local loc = require("wyt.localization")
local M = {}

-- Función agnóstica para llamar al LLM
function M.generate_text(prompt)
    local provider = config.options.llm_provider
    local api_key = config.options.api_key
    -- Aquí iría la lógica para llamar a la API correspondiente
    -- Por ahora, solo simula la respuesta
    if provider == "openai" then
        return "[OpenAI] Generated text for: " .. prompt
    elseif provider == "claude" then
        return "[Claude] Generated text for: " .. prompt
    else
        return loc.t("provider_not_supported")
    end
end

return M
