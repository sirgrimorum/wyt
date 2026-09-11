-- P3: per-text-type configuration — guided questions, paragraph behavior, section depth
local kinds = require("wyt.section_kinds")

local M = {}

-- `outline` says what a name becomes in the export, per plan level, counting the
-- root as level 1. A heading level sets it; `break_with` prints a separator
-- instead, which is how prose marks a scene change; nothing at all means the
-- text simply runs on. `groups` covers the group markers inside `text.wyt.md`,
-- which are structure for WYT and not part of the finished document.
-- The root itself is always the document title, so no type declares level 1.
local SCENE = "* * *"

-- `idea_prompt` is the single orienting question shown when adding one free-form
-- idea; `subsection_idea_prompt` replaces it inside a section, where the writer
-- is filling in a part rather than opening a new line of thought. The multi-item
-- `idea_questions` list is only used by the guided brainstorming mode.
--
-- `label` and `blurb` are what the writer reads in the project wizard, and
-- `label` is also the name the model is given for the type: the raw id would
-- send `long_novel` into a Spanish prompt. `prose_kind` names the paragraph the
-- model is asked for, since an essay does not want the same one as a novel. All
-- three are noun phrases with their article, so they drop into a sentence.
M.configs = {
    novel = {
        label = { en = "Novel", es = "Novela" },
        blurb = {
            en = "Titled chapters, scenes separated inside them.",
            es = "Capítulos con título, escenas separadas dentro de ellos.",
        },
        prose_kind = { en = "a narrative paragraph", es = "un párrafo narrativo" },
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
        group_prompt = {
            en = "What chapter or scene do these ideas form?",
            es = "¿Qué capítulo o escena forman estas ideas?",
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
        -- chapters are titled, scenes are separated
        outline = { levels = { [2] = { heading = 2 }, [3] = { break_with = SCENE } }, groups = {} },
        section_kinds = kinds.narrative,
    },

    -- A long novel is a novel with one more level between the book and the
    -- scene: parts or books, then chapters, then scenes.
    long_novel = {
        label = { en = "Long novel", es = "Novela larga" },
        blurb = {
            en = "Parts and chapters titled, scenes separated inside them.",
            es = "Partes y capítulos con título, escenas separadas dentro de ellos.",
        },
        prose_kind = { en = "a narrative paragraph", es = "un párrafo narrativo" },
        idea_prompt = {
            en = "What thread or event moves the whole story forward?",
            es = "¿Qué hilo o suceso hace avanzar toda la historia?",
        },
        subsection_idea_prompt = {
            en = "What moment or turn belongs to this part?",
            es = "¿Qué momento o giro pertenece a esta parte?",
        },
        idea_questions = {
            en = {
                "What is the through-line the whole book follows?",
                "What part or book does this belong to?",
                "Which subplot does this feed, and where does it rejoin the main one?",
                "Which characters change here, and how far along are they?",
                "When does this happen relative to what came before?",
                "What does the reader learn here that they could not learn earlier?",
            },
            es = {
                "¿Cuál es el hilo conductor que sigue todo el libro?",
                "¿A qué parte o libro pertenece esto?",
                "¿Qué trama secundaria alimenta, y dónde vuelve a la principal?",
                "¿Qué personajes cambian aquí, y cuánto han avanzado ya?",
                "¿Cuándo ocurre esto respecto a lo anterior?",
                "¿Qué descubre aquí el lector que no podía descubrir antes?",
            },
        },
        group_prompt = {
            en = "What part, chapter or arc do these ideas form?",
            es = "¿Qué parte, capítulo o arco forman estas ideas?",
        },
        group_questions = {
            en = {
                "What part or book do these ideas belong to?",
                "What arc do they complete within it?",
                "What has to be true before this can happen?",
            },
            es = {
                "¿A qué parte o libro pertenecen estas ideas?",
                "¿Qué arco completan dentro de ella?",
                "¿Qué debe ser cierto antes de que esto ocurra?",
            },
        },
        group_name_hint = {
            en = "Part, chapter or arc title:",
            es = "Título de la parte, capítulo o arco:",
        },
        -- one idea → one paragraph
        multi_idea_paragraph = false,
        section_depth = 4,
        -- parts and chapters are titled, scenes are separated
        outline = {
            levels = { [2] = { heading = 2 }, [3] = { heading = 3 }, [4] = { break_with = SCENE } },
            groups = {},
        },
        section_kinds = kinds.narrative,
    },

    -- The middle ground: longer than a story, but told in scenes rather than
    -- chapters, so level 2 is the scene itself and nothing is titled.
    short_novel = {
        label = { en = "Short novel", es = "Novela corta" },
        blurb = {
            en = "Told in scenes, separated and never titled.",
            es = "Contada en escenas, separadas y nunca tituladas.",
        },
        prose_kind = { en = "a narrative paragraph", es = "un párrafo narrativo" },
        idea_prompt = {
            en = "What scene do you want to write?",
            es = "¿Qué escena quieres escribir?",
        },
        subsection_idea_prompt = {
            en = "What happens inside this scene?",
            es = "¿Qué ocurre dentro de esta escena?",
        },
        idea_questions = {
            en = {
                "What scene is this, and who is in it?",
                "What does the point-of-view character want in it?",
                "What goes wrong, or differently than expected?",
                "What is different by the end of it?",
                "What does it set up for the scene after?",
            },
            es = {
                "¿Qué escena es esta, y quién está en ella?",
                "¿Qué quiere en ella el personaje desde cuyo punto de vista se narra?",
                "¿Qué sale mal, o distinto de lo esperado?",
                "¿Qué ha cambiado al terminar?",
                "¿Qué prepara para la escena siguiente?",
            },
        },
        group_prompt = {
            en = "What scene do these ideas form?",
            es = "¿Qué escena forman estas ideas?",
        },
        group_questions = {
            en = {
                "What scene do these ideas form?",
                "Where does it start, and where does it cut?",
            },
            es = {
                "¿Qué escena forman estas ideas?",
                "¿Dónde empieza, y dónde corta?",
            },
        },
        group_name_hint = {
            en = "Scene name:",
            es = "Nombre de la escena:",
        },
        multi_idea_paragraph = false,
        section_depth = 2,
        -- scenes are separated, never titled
        outline = { levels = { [2] = { break_with = SCENE } }, groups = {} },
        section_kinds = kinds.narrative,
    },

    short_story = {
        label = { en = "Short story", es = "Cuento" },
        blurb = {
            en = "One flow of scenes under the story's title.",
            es = "Un solo flujo de escenas bajo el título del cuento.",
        },
        prose_kind = { en = "a literary paragraph", es = "un párrafo literario" },
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
        group_prompt = {
            en = "What story beat do these ideas form?",
            es = "¿Qué momento narrativo forman estas ideas?",
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
        -- one flow of scenes under the story's title
        outline = { levels = {}, groups = { break_with = SCENE } },
        section_kinds = kinds.narrative,
    },

    essay = {
        label = { en = "Essay", es = "Ensayo" },
        blurb = {
            en = "Titled sections, their paragraphs running on.",
            es = "Secciones con título, y sus párrafos corren seguidos.",
        },
        prose_kind = { en = "an argumentative paragraph", es = "un párrafo argumentativo" },
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
        group_prompt = {
            en = "What central argument unites these ideas?",
            es = "¿Cuál es el argumento central que une estas ideas?",
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
        -- sections are titled, the paragraphs inside them run on
        outline = { levels = { [2] = { heading = 2 } }, groups = {} },
        section_kinds = kinds.argument,
    },

    summary = {
        label = { en = "Summary", es = "Resumen" },
        blurb = {
            en = "Labelled notes, a whole group condensed into one paragraph.",
            es = "Notas etiquetadas, y un grupo entero se condensa en un párrafo.",
        },
        prose_kind = { en = "a concise paragraph of notes", es = "un párrafo de notas conciso" },
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
        group_prompt = {
            en = "What topic do these ideas summarize?",
            es = "¿Qué tema resumen estas ideas?",
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
        -- notes read best labelled, so here the group names do become headings
        outline = { levels = {}, groups = { heading = 2 } },
        section_kinds = kinds.notes,
    },
}

function M.get(type_name)
    return M.configs[type_name] or M.configs.essay
end

--- The archetypes a project of this type can give its sections.
function M.section_kinds(type_name)
    return M.get(type_name).section_kinds or kinds.narrative
end

--- One archetype by id, or nil. `prose` and an unknown id both return nil: they
--- mean the section is guided by its project type and nothing else.
function M.section_kind(type_name, kind_id)
    if not kind_id or kind_id == "" or kind_id == "prose" then return nil end
    for _, kind in ipairs(M.section_kinds(type_name)) do
        if kind.id == kind_id then return kind end
    end
    return nil
end

--- Where a section's guides come from. An archetype answers for the fields it
--- defines and the project type answers for the rest, so a Characters section of
--- a novel asks about wounds and wants but still knows it is inside a novel.
local function guide(type_name, kind_id, field)
    local kind = M.section_kind(type_name, kind_id)
    if kind and kind[field] then return kind[field] end
    return M.get(type_name)[field]
end

local function localized(entry, lang)
    if not entry then return nil end
    return entry[lang] or entry.en
end

--- The type's name in the writer's language. This is also the name the model is
--- given: the id is English and carries an underscore, so `long_novel` would go
--- into a Spanish prompt untranslated.
function M.label(type_name, lang)
    return localized(M.get(type_name).label, lang) or type_name
end

--- One line on what the type does to the text, for the wizard's list.
function M.blurb(type_name, lang)
    return localized(M.get(type_name).blurb, lang) or ""
end

--- What the project wizard shows for one type: its name, then what it does.
function M.menu_label(type_name, lang)
    local blurb = M.blurb(type_name, lang)
    if blurb == "" then return M.label(type_name, lang) end
    return M.label(type_name, lang) .. ": " .. blurb
end

--- The paragraph this type asks the model for, as a noun phrase with its
--- article, so it drops straight into a prompt sentence.
function M.prose_kind(type_name, lang)
    return localized(M.get(type_name).prose_kind, lang)
end

--- Single orienting question for one free-form idea.
--- Returns nil when neither the section's archetype nor the type defines one, so
--- the caller can fall back to the generic "Enter idea name:" prompt.
function M.idea_prompt(type_name, lang, is_subsection, kind_id)
    local field = is_subsection and "subsection_idea_prompt" or "idea_prompt"
    return localized(guide(type_name, kind_id, field), lang)
end

function M.idea_questions(type_name, lang, kind_id)
    return localized(guide(type_name, kind_id, "idea_questions"), lang)
end

--- Single orienting question for naming a group. Returns nil when none is
--- defined, so the caller can fall back to `group_name_hint`.
function M.group_prompt(type_name, lang, kind_id)
    return localized(guide(type_name, kind_id, "group_prompt"), lang)
end

function M.group_questions(type_name, lang, kind_id)
    return localized(guide(type_name, kind_id, "group_questions"), lang)
end

function M.group_name_hint(type_name, lang, kind_id)
    return localized(guide(type_name, kind_id, "group_name_hint"), lang)
end

--- True when the type gathers a whole group into one paragraph instead of one
--- paragraph per idea. Read when a group is implemented into `text.wyt.md`.
function M.multi_idea_paragraph(type_name)
    return M.get(type_name).multi_idea_paragraph
end

--- How many plan levels the type allows, counting the project root as level 1.
--- A section at a level below the limit may hold sub-sections; one at the limit
--- writes its groups straight to `text.wyt.md`.
function M.section_depth(type_name)
    return M.get(type_name).section_depth or 1
end

--- What a section name at `level` becomes in the export, counting the root as
--- level 1: `{ heading = n }`, `{ break_with = "* * *" }`, or nil for nothing.
function M.outline(type_name, level)
    local outline = M.get(type_name).outline
    if not outline then return nil end
    return outline.levels and outline.levels[level] or nil
end

--- The same, for the group markers inside `text.wyt.md`. Most types render
--- nothing: the markers are structure, not part of the finished document.
function M.group_outline(type_name)
    local outline = M.get(type_name).outline
    if not outline or not outline.groups then return nil end
    return next(outline.groups) and outline.groups or nil
end

--- Type names the project wizard offers, in the order it offers them.
function M.names()
    return { "novel", "long_novel", "short_novel", "short_story", "essay", "summary" }
end

return M
