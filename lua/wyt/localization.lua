local M = {}

M.translations = {
    en = {
        no_project = "[WYT] No project found in current directory. Please navigate to your project root.",
        config_updated = "[WYT] Configuration updated: ",
        provider_not_supported = "[WYT] Provider not supported.",
        result = "[WYT] Result:\n",
        set_provider = "Set LLM provider and API Key",
        generate_text = "Generate literary text using configured LLM",
        choose_lang = "Choose project language:",
        choose_type = "Choose literary text type:",
        choose_path = "Enter base path for the project:",
        choose_name = "Enter project name:",
        choose_content_type = "Choose main section content type:",
        content = "Content",
        definition = "Definition",
        has_sections = "Will the main section have sub-sections?",
        yes = "Yes",
        no = "No",
        open_where = "Open project in:",
        same_window = "Same window",
        new_window = "New window",
        plan_intro = "Project plan and guide.",
        text_intro = "Start writing your text here.",
        export_intro = "Final exported text.",
        project_created = "[WYT] Project created at: ",
        new_usage = "[WYT] Usage: :WYTNew p<tab>",
        new_desc = "Create new WYT entity ([p]roject, [i]dea, [g]roup, etc.)",
        idea_name = "Enter idea name:",
        use_llm = "Use LLM to improve/redact the idea?",
        add_to_group = "Add idea to an existing group?",
        idea_added = "[WYT] Idea added: ",
    },
    es = {
        no_project = "[WYT] No se encontró ningún proyecto en el directorio actual. Por favor, navega a la raíz de tu proyecto.",
        config_updated = "[WYT] Configuración actualizada: ",
        provider_not_supported = "[WYT] Proveedor no soportado.",
        result = "[WYT] Resultado:\n",
        set_provider = "Configura el proveedor LLM y la API Key",
        generate_text = "Genera texto literario usando el LLM configurado",
        choose_lang = "Elige el idioma del proyecto:",
        choose_type = "Elige el tipo de texto literario:",
        choose_path = "Ingresa la ruta base para el proyecto:",
        choose_name = "Ingresa el nombre del proyecto:",
        choose_content_type = "Elige el tipo de contenido de la sección principal:",
        content = "Contenido",
        definition = "Definición",
        has_sections = "¿La sección principal tendrá sub-secciones?",
        yes = "Sí",
        no = "No",
        open_where = "Abrir proyecto en:",
        same_window = "Misma ventana",
        new_window = "Nueva ventana",
        plan_intro = "Plan y guía del proyecto.",
        text_intro = "Comienza a escribir tu texto aquí.",
        export_intro = "Texto final exportado.",
        project_created = "[WYT] Proyecto creado en: ",
        new_usage = "[WYT] Uso: :WYTNew p<tab>",
        new_desc = "Crear nueva entidad WYT ([p]royecto, [i]dea, [g]rupo, etc.)",
        idea_name = "Ingresa el nombre de la idea:",
        use_llm = "¿Usar LLM para mejorar/redactar la idea?",
        add_to_group = "¿Agregar la idea a un grupo existente?",
        idea_added = "[WYT] Idea agregada: ",
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


function M.get_lang()
    return lang
end

return M
