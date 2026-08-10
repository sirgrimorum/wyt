-- Section archetypes: what a section is *for*, as opposed to what literary type
-- the project is. A novel's root can hold the prose itself, but also a cast of
-- characters, a chronology of events, or the turning points that shape them, and
-- each of those is worked on with different questions.
--
-- A kind carries its own guides. Where it defines a prompt the section uses it;
-- where it does not, the project type's own prompt still applies (see
-- `types.guide`). `content_type` decides whether the section reaches the export
-- or stays reference material that only `:WYTSearch` sees.
--
-- Labels carry a gloss in parentheses: the craft word is the precise one, and
-- the gloss is for the writer who has not met it before.
local M = {}

local prose = {
    id = "prose",
    label = {
        en = "Prose (the text itself)",
        es = "Prosa (el texto mismo)",
    },
    content_type = "content",
    -- No guides of its own: the project type's questions are the right ones.
}

local characters = {
    id = "characters",
    label = {
        en = "Characters (who the story happens to)",
        es = "Personajes (a quién le ocurre la historia)",
    },
    content_type = "definition",
    group_prompt = {
        en = "Which character is this?",
        es = "¿De qué personaje se trata?",
    },
    group_name_hint = {
        en = "Character name:",
        es = "Nombre del personaje:",
    },
    idea_prompt = {
        en = "What do we need to know about this character?",
        es = "¿Qué necesitamos saber de este personaje?",
    },
    subsection_idea_prompt = {
        en = "What detail of this character belongs here?",
        es = "¿Qué detalle de este personaje va aquí?",
    },
    idea_questions = {
        en = {
            "What does this character want, and what do they need instead?",
            "What wound or belief sits behind that want?",
            "What do they do when they are afraid?",
            "How do they speak, and what do they never say?",
            "Who can make them change their mind?",
        },
        es = {
            "¿Qué quiere este personaje, y qué necesita en realidad?",
            "¿Qué herida o creencia hay detrás de ese deseo?",
            "¿Qué hace cuando tiene miedo?",
            "¿Cómo habla, y qué es lo que nunca dice?",
            "¿Quién puede hacerle cambiar de opinión?",
        },
    },
}

local setting = {
    id = "setting",
    label = {
        en = "Setting (where and when it takes place)",
        es = "Escenario (dónde y cuándo ocurre)",
    },
    content_type = "definition",
    group_prompt = {
        en = "Which place or world is this?",
        es = "¿Qué lugar o mundo es este?",
    },
    group_name_hint = {
        en = "Place name:",
        es = "Nombre del lugar:",
    },
    idea_prompt = {
        en = "What about this place matters to the story?",
        es = "¿Qué de este lugar importa a la historia?",
    },
    subsection_idea_prompt = {
        en = "What detail of this place belongs here?",
        es = "¿Qué detalle de este lugar va aquí?",
    },
    idea_questions = {
        en = {
            "What does this place look, sound and smell like?",
            "Who belongs here, and who does not?",
            "What rule of this world would surprise a stranger?",
            "How does this place limit what the characters can do?",
        },
        es = {
            "¿Cómo se ve, suena y huele este lugar?",
            "¿Quién pertenece aquí, y quién no?",
            "¿Qué regla de este mundo sorprendería a un forastero?",
            "¿Cómo limita este lugar lo que los personajes pueden hacer?",
        },
    },
}

local chronology = {
    id = "chronology",
    label = {
        en = "Chronology (when things happen, in story order)",
        es = "Cronología (cuándo ocurre todo, en orden de la historia)",
    },
    content_type = "definition",
    group_prompt = {
        en = "What period or day do these events belong to?",
        es = "¿A qué periodo o día pertenecen estos hechos?",
    },
    group_name_hint = {
        en = "Period, day or date:",
        es = "Periodo, día o fecha:",
    },
    idea_prompt = {
        en = "What happens at this point in time?",
        es = "¿Qué ocurre en este momento?",
    },
    subsection_idea_prompt = {
        en = "What else happens within this period?",
        es = "¿Qué más ocurre dentro de este periodo?",
    },
    idea_questions = {
        en = {
            "What happens here, in one sentence?",
            "What had to happen before this could?",
            "Who knows about it, and who does not yet?",
            "How long after the previous event is this?",
            "Where does the reader learn about it, if not here?",
        },
        es = {
            "¿Qué ocurre aquí, en una frase?",
            "¿Qué tuvo que ocurrir antes para que esto pudiera pasar?",
            "¿Quién lo sabe, y quién todavía no?",
            "¿Cuánto tiempo pasa desde el hecho anterior?",
            "¿Dónde se entera el lector, si no es aquí?",
        },
    },
}

local turning_points = {
    id = "turning_points",
    label = {
        en = "Turning points (what changes everything)",
        es = "Puntos de giro (lo que lo cambia todo)",
    },
    content_type = "definition",
    group_prompt = {
        en = "Whose life, or which thread, does this turn?",
        es = "¿Qué vida, o qué hilo, hace girar esto?",
    },
    group_name_hint = {
        en = "Turning point:",
        es = "Punto de giro:",
    },
    idea_prompt = {
        en = "What changes here, and for whom?",
        es = "¿Qué cambia aquí, y para quién?",
    },
    subsection_idea_prompt = {
        en = "What else turns at this point?",
        es = "¿Qué más gira en este punto?",
    },
    idea_questions = {
        en = {
            "What is no longer possible after this?",
            "What does the character believe before it, and after?",
            "Who or what forces the change?",
            "What does it cost them?",
            "Where does the reader feel it first?",
        },
        es = {
            "¿Qué deja de ser posible después de esto?",
            "¿Qué cree el personaje antes, y qué cree después?",
            "¿Quién o qué fuerza el cambio?",
            "¿Qué le cuesta?",
            "¿Dónde lo siente primero el lector?",
        },
    },
}

local themes = {
    id = "themes",
    label = {
        en = "Themes (what the work is about underneath)",
        es = "Temas (de qué trata la obra por debajo)",
    },
    content_type = "definition",
    group_prompt = {
        en = "What theme runs through these ideas?",
        es = "¿Qué tema recorre estas ideas?",
    },
    group_name_hint = {
        en = "Theme:",
        es = "Tema:",
    },
    idea_prompt = {
        en = "How does the work say this without stating it?",
        es = "¿Cómo lo dice la obra sin enunciarlo?",
    },
    subsection_idea_prompt = {
        en = "What else carries this theme?",
        es = "¿Qué más lleva este tema?",
    },
    idea_questions = {
        en = {
            "Which scene carries this theme without naming it?",
            "Which character argues the other side of it?",
            "What image or object keeps returning with it?",
            "What would be lost if this theme were cut?",
        },
        es = {
            "¿Qué escena lleva este tema sin nombrarlo?",
            "¿Qué personaje defiende la otra cara?",
            "¿Qué imagen u objeto vuelve una y otra vez con él?",
            "¿Qué se perdería si se quitara este tema?",
        },
    },
}

local key_concepts = {
    id = "key_concepts",
    label = {
        en = "Key concepts (the terms the argument rests on)",
        es = "Conceptos clave (los términos en que se apoya el argumento)",
    },
    content_type = "definition",
    group_prompt = {
        en = "Which concept is this?",
        es = "¿De qué concepto se trata?",
    },
    group_name_hint = {
        en = "Concept:",
        es = "Concepto:",
    },
    idea_prompt = {
        en = "How do you define this concept here?",
        es = "¿Cómo defines este concepto aquí?",
    },
    subsection_idea_prompt = {
        en = "What else belongs to this definition?",
        es = "¿Qué más pertenece a esta definición?",
    },
    idea_questions = {
        en = {
            "How would you define it in one sentence?",
            "Who uses this term differently, and how?",
            "What example makes it concrete?",
            "What is it commonly confused with?",
        },
        es = {
            "¿Cómo lo definirías en una frase?",
            "¿Quién usa este término de otra forma, y cómo?",
            "¿Qué ejemplo lo hace concreto?",
            "¿Con qué se confunde habitualmente?",
        },
    },
}

local sources = {
    id = "sources",
    label = {
        en = "Sources (the evidence you are citing)",
        es = "Fuentes (la evidencia que citas)",
    },
    content_type = "definition",
    group_prompt = {
        en = "Which source or author is this?",
        es = "¿Qué fuente o autor es este?",
    },
    group_name_hint = {
        en = "Author or work:",
        es = "Autor u obra:",
    },
    idea_prompt = {
        en = "What does this source let you claim?",
        es = "¿Qué te permite afirmar esta fuente?",
    },
    subsection_idea_prompt = {
        en = "What else does this source support?",
        es = "¿Qué más sostiene esta fuente?",
    },
    idea_questions = {
        en = {
            "What exactly does it show, and what does it not?",
            "Which passage or figure will you cite?",
            "Who disputes it?",
            "Where in the text does it belong?",
        },
        es = {
            "¿Qué muestra exactamente, y qué no?",
            "¿Qué pasaje o dato vas a citar?",
            "¿Quién lo discute?",
            "¿En qué parte del texto encaja?",
        },
    },
}

-- Counterarguments are written, not just collected, so this one is content: it
-- reaches the export like any other section of the essay.
local counterarguments = {
    id = "counterarguments",
    label = {
        en = "Counterarguments (the objections you answer)",
        es = "Contraargumentos (las objeciones que respondes)",
    },
    content_type = "content",
    group_prompt = {
        en = "Which objection does this group answer?",
        es = "¿Qué objeción responde este grupo?",
    },
    group_name_hint = {
        en = "Objection:",
        es = "Objeción:",
    },
    idea_prompt = {
        en = "What objection do you have to answer?",
        es = "¿Qué objeción tienes que responder?",
    },
    subsection_idea_prompt = {
        en = "What else does this objection require?",
        es = "¿Qué más exige esta objeción?",
    },
    idea_questions = {
        en = {
            "Who would raise this objection, and why?",
            "What is the strongest version of it?",
            "What does your answer concede?",
            "What evidence settles it?",
        },
        es = {
            "¿Quién plantearía esta objeción, y por qué?",
            "¿Cuál es su versión más fuerte?",
            "¿Qué concede tu respuesta?",
            "¿Qué evidencia la resuelve?",
        },
    },
}

M.narrative = { prose, characters, setting, chronology, turning_points, themes }
M.argument  = { prose, key_concepts, sources, counterarguments, themes }
M.notes     = { prose, key_concepts, sources }

return M
