-- P3: per-text-type configuration — guided questions, paragraph behavior, section depth
local M = {}

-- `idea_prompt` is the single orienting question shown when adding one free-form
-- idea; `subsection_idea_prompt` replaces it inside a section, where the writer
-- is filling in a part rather than opening a new line of thought. The multi-item
-- `idea_questions` list is only used by the guided brainstorming mode.
M.configs = {
    novel = {
        idea_prompt = {
            en = "What happens next in your story?",
            es = "¿Qué ocurre a continuación en tu historia?",
        },
        subsection_idea_prompt = {
            en = "What detail or moment brings this scene to life?",
            es = "¿Qué detalle o momento da vida a esta escena?",
        },
        idea_questions = {
            en = {
                "What happens in this scene or chapter?",
                "What does the main character want, fear, or avoid?",
                "What conflict arises and how does it escalate?",
                "What is revealed about the world or characters?",
                "What emotional tone or atmosphere dominates?",
            },
            es = {
                "¿Qué ocurre en esta escena o capítulo?",
                "¿Qué quiere, teme o evita el personaje principal?",
                "¿Qué conflicto surge y cómo escala?",
                "¿Qué se revela sobre el mundo o los personajes?",
                "¿Qué tono emocional o atmósfera predomina?",
            },
        },
        group_questions = {
            en = {
                "What narrative arc do these ideas form?",
                "What chapter or section could these ideas become?",
                "What is the dramatic turning point?",
            },
            es = {
                "¿Qué arco narrativo forman estas ideas?",
                "¿En qué capítulo o sección podrían convertirse?",
                "¿Cuál es el punto de giro dramático?",
            },
        },
        group_name_hint = {
            en = "Chapter or scene title:",
            es = "Título del capítulo o escena:",
        },
        -- one idea → one paragraph
        multi_idea_paragraph = false,
        section_depth = 3,
    },

    short_story = {
        idea_prompt = {
            en = "What moment or image do you want to capture?",
            es = "¿Qué momento o imagen quieres capturar?",
        },
        subsection_idea_prompt = {
            en = "What detail reveals this moment?",
            es = "¿Qué detalle revela este momento?",
        },
        idea_questions = {
            en = {
                "What is the central image or moment?",
                "How does the protagonist change from start to end?",
                "What detail most reveals character or theme?",
                "What is the story's emotional core?",
            },
            es = {
                "¿Cuál es la imagen o momento central?",
                "¿Cómo cambia el protagonista del inicio al final?",
                "¿Qué detalle revela más el personaje o el tema?",
                "¿Cuál es el núcleo emocional de la historia?",
            },
        },
        group_questions = {
            en = {
                "What story beat does this group represent?",
                "Is this setup, confrontation, or resolution?",
            },
            es = {
                "¿Qué momento narrativo representa este grupo?",
                "¿Es planteamiento, confrontación o resolución?",
            },
        },
        group_name_hint = {
            en = "Story beat or section name:",
            es = "Momento narrativo o nombre de sección:",
        },
        multi_idea_paragraph = false,
        section_depth = 1,
    },

    essay = {
        idea_prompt = {
            en = "What argument or perspective do you want to explore in this essay?",
            es = "¿Qué argumento o perspectiva quieres explorar en este ensayo?",
        },
        subsection_idea_prompt = {
            en = "What evidence or example best illustrates this part?",
            es = "¿Qué evidencia o ejemplo ilustra mejor esta parte?",
        },
        idea_questions = {
            en = {
                "What argument or claim does this idea support?",
                "What evidence or example illustrates this?",
                "What counterargument should be addressed?",
                "How does this connect to the central thesis?",
            },
            es = {
                "¿Qué argumento o afirmación apoya esta idea?",
                "¿Qué evidencia o ejemplo la ilustra?",
                "¿Qué contraargumento debe abordarse?",
                "¿Cómo se conecta con la tesis central?",
            },
        },
        group_questions = {
            en = {
                "What paragraph or section does this group form?",
                "What is the topic sentence for this group?",
            },
            es = {
                "¿Qué párrafo o sección forma este grupo?",
                "¿Cuál es la oración temática de este grupo?",
            },
        },
        group_name_hint = {
            en = "Section or argument name:",
            es = "Nombre de la sección o argumento:",
        },
        multi_idea_paragraph = false,
        section_depth = 2,
    },

    summary = {
        idea_prompt = {
            en = "What key point do you want to record?",
            es = "¿Qué punto clave quieres registrar?",
        },
        subsection_idea_prompt = {
            en = "What supporting detail belongs here?",
            es = "¿Qué detalle de apoyo va aquí?",
        },
        idea_questions = {
            en = {
                "What key point must the reader take away?",
                "What supporting detail is essential (not decorative)?",
                "What can be omitted or condensed?",
                "How does this connect to the main conclusion?",
            },
            es = {
                "¿Qué punto clave debe quedarse el lector?",
                "¿Qué detalle de apoyo es esencial (no decorativo)?",
                "¿Qué puede omitirse o condensarse?",
                "¿Cómo conecta con la conclusión principal?",
            },
        },
        group_questions = {
            en = {
                "What topic does this group summarize?",
                "Can these ideas be merged into a single point?",
            },
            es = {
                "¿Qué tema resume este grupo?",
                "¿Pueden estas ideas unirse en un solo punto?",
            },
        },
        group_name_hint = {
            en = "Topic being summarized:",
            es = "Tema que se resume:",
        },
        -- summary: multiple ideas combine into one paragraph
        multi_idea_paragraph = true,
        section_depth = 1,
    },
}

function M.get(type_name)
    return M.configs[type_name] or M.configs.essay
end

--- Single orienting question for one free-form idea.
--- Returns nil when the type defines none, so the caller can fall back to the
--- generic "Enter idea name:" prompt.
function M.idea_prompt(type_name, lang, is_subsection)
    local cfg = M.get(type_name)
    local entry = (is_subsection and cfg.subsection_idea_prompt) or cfg.idea_prompt
    if not entry then return nil end
    return entry[lang] or entry.en
end

function M.idea_questions(type_name, lang)
    local cfg = M.get(type_name)
    return cfg.idea_questions[lang] or cfg.idea_questions.en
end

function M.group_questions(type_name, lang)
    local cfg = M.get(type_name)
    return cfg.group_questions[lang] or cfg.group_questions.en
end

function M.group_name_hint(type_name, lang)
    local cfg = M.get(type_name)
    return cfg.group_name_hint[lang] or cfg.group_name_hint.en
end

function M.multi_idea_paragraph(type_name)
    return M.get(type_name).multi_idea_paragraph
end

return M
