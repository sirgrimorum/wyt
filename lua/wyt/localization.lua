local M = {}

M.translations = {
    en = {
        config_updated = "[WYT] Configuration updated: ",
        provider_not_supported = "[WYT] Provider not supported.",
        result = "[WYT] Result:\n",
        set_provider = "Set LLM provider and API Key",
        generate_text = "Generate literary text using configured LLM"
    },
    es = {
        config_updated = "[WYT] Configuración actualizada: ",
        provider_not_supported = "[WYT] Proveedor no soportado.",
        result = "[WYT] Resultado:\n",
        set_provider = "Configura el proveedor LLM y la API Key",
        generate_text = "Genera texto literario usando el LLM configurado"
    }
}

M.lang = "en"

function M.set_lang(lang)
    if M.translations[lang] then
        M.lang = lang
    end
end

function M.t(key)
    return M.translations[M.lang][key] or key
end

return M
