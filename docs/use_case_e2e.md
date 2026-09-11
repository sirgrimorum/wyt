# WYT — End-to-End Use Case

A complete walkthrough of the WYT methodology using every command, keymap, and option.
The example project is a **short essay** titled *"The Silence of Cities"*.

This is the worked example. The rules it exercises, the commands, the keymaps,
the project types and the section archetypes, are documented once in the
[User Guide](../USER_GUIDE.md); this document shows them in use, in order, from
an empty directory to a finished export.

---

## 0. Prerequisites

```vim
" In your Neovim config (init.lua / lazy.nvim):
{
  "your/wyt",
  config = function()
    require("wyt").setup()
  end
}
```

Verify the plugin is healthy before starting:

```vim
:checkhealth wyt
```

Expected output:
- Neovim >= 0.9 ✓
- `telescope.nvim` installed ✓
- `git` executable found ✓
- (optional) current buffer is a WYT project

---

## 1. Configure LLM Provider

Before using AI-assisted features, set your provider. Give the command the
provider **only**, and let it ask for the key:

```vim
:WYTConfig openai
" or
:WYTConfig claude
```

The key is then read with `inputsecret`, so it is not echoed and never reaches
`:history`. Passing it as a second argument still works, but WYT warns and
scrubs the command out of the history, because Neovim would otherwise persist it
to the shada file.

This saves the provider and key to the global plugin config. Only needs to be
done once per Neovim session (or persisted via your own config).

---

## 2. Create a New Project

```vim
:WYTNew p
```

Interactive wizard prompts:

| Prompt | Example answer |
|--------|----------------|
| Language | `es` |
| Text type | `Ensayo: Secciones con título, y sus párrafos corren seguidos.` |
| Path | `/home/user/writing` (pre-filled with the current directory) |
| Project name | `The Silence of Cities` |
| Root folder name | `the-silence-of-cities` (pre-filled with the slug; `.` = use the path itself) |
| Content type | `content` |
| Has sections? | `Yes` |
| Open in | `Same window` |

Six text types are offered. The list is shown in the language picked one
question earlier, each entry naming the type and what it does to the finished
text, so the answer above reads `Ensayo: ...` and not `essay`. The ids
`novel`, `long_novel`, `short_novel`, `short_story`, `essay` and `summary` are
what gets written to `config.wyt.yml`; they are never shown and never sent to
the model. See the [User Guide](../USER_GUIDE.md#tipos-de-texto).

**Has sections?** is only asked for a type that allows more than one plan level:
`short_story` and `summary` are single-level, so the wizard writes
`sections: false` without asking.

Every prompt after the Language step is shown in the language you picked, and
`<Esc>` at any step cancels the wizard without creating anything.

What happens automatically:
- `/home/user/writing/the-silence-of-cities/` directory is created
- `config.wyt.yml` is written with language, type, content_type, sections
- `plan.wyt.md` is created with the project name, empty Description, Ideas, and Groups sections
- `export.wyt.md` is created (empty placeholder)
- `git init` runs and an initial commit is made
- `plan.wyt.md` opens in the current buffer

**Resulting `config.wyt.yml`:**
```yaml
lang: es
type: essay
content_type: content
sections: true
name: The Silence of Cities
```

**Resulting `plan.wyt.md`:**
```markdown
# The Silence of Cities

## Descripción

## Ideas

## Grupos
```

---

## 3. Write the Project Description

With `plan.wyt.md` open, fill in the Description section manually:

```markdown
## Descripción

Un ensayo sobre cómo el ruido constante de las ciudades modernas ha silenciado
la capacidad de reflexión individual. Explora el contraste entre el ruido
exterior y el silencio interior necesario para pensar.
```

Save the file:
```vim
:w
```

The `BufWritePost` autocmd fires automatically:
- `git add . && git commit -m "Save: plan.wyt.md"` runs in the background
- No user action required

---

## 4. Brainstorm Ideas

### 4a. Manual idea

```vim
:WYTNew i
```

Flow:
1. Plugin asks how to brainstorm: **Enter a free-form idea** / **Answer guided
   questions**. Pick the first.
2. Plugin shows the single orienting question for `essay` type:
   *"¿Qué argumento o perspectiva quieres explorar en este ensayo?"*
3. User types: `El ruido urbano suprime la capacidad de escuchar el propio pensamiento`
4. Plugin asks **Improve with LLM?**, as a menu with *Yes* and *No*. Every
   yes/no in WYT is a menu, never a typed `y`.
5. Pick *Yes*. The refined sentence appears in full in a panel titled
   *Idea mejorada* above the menu, and the menu decides what happens to it. The
   result is never applied on its own:

   | Option | Effect |
   |--------|--------|
   | Keep this version | store the generated sentence |
   | Edit this version | open it in an input, pre-filled, to adjust |
   | Generate another | ask again for a clearly different version |
   | Keep my original | discard the generation, store what you typed |

   `<Esc>` is the same as *Keep my original*.
6. No group exists yet, so nothing is asked about groups. Once the plan has
   groups, this is where a multi-select of them appears, and the new idea is
   tagged into every group you tick.
7. Idea is appended to `## Ideas`

### The guided questions mode

The second mode, **Answer guided questions**, starts with a short note saying
how many questions are coming, that each answer becomes its own idea, that a
blank answer skips one, and that `<Esc>` stops early and keeps whatever you have
answered. The questions then come one at a time, each labelled with its
position, for example `(2/4) ¿Qué evidencia o ejemplo la ilustra?`.

With LLM improvement on, each collected idea is refined and reviewed in turn,
and the run ends on a single confirmation line.

### If the model needs a clarification

The prompt tells the model to rewrite rather than ask. When an idea really is
ambiguous, it may reply with one short question and 2 to 4 short options, which
WYT shows as a normal selection menu plus **Skip / not sure**. Your answer is
fed back into the next attempt. Skipping, or a second question, forces the model
to commit to a rewrite.

The idea is always stored as a single line. If the model replies with a question
it cannot render as a menu, or with anything else unusable, WYT reports it and
keeps your text.

### 4b. More ideas (repeat `:WYTNew i`)

Add several more ideas the same way:

- `La arquitectura urbana moderna elimina espacios para la contemplación`
- `El smartphone es una extensión del ruido urbano dentro del hogar`
- `Las ciudades medievales tenían plazas diseñadas para el silencio y la reflexión`
- `El silencio es condición necesaria para la creatividad según múltiples estudios`
- `El capitalismo de atención explota la incapacidad de estar en silencio`
- `Las personas en ciudades duermen peor que en zonas rurales`
- `Movimientos slow-living como respuesta al exceso de ruido`

After each save, the auto-commit fires silently.

**`plan.wyt.md` Ideas section now looks like:**
```markdown
## Ideas

- El ruido urbano suprime la capacidad de escuchar el propio pensamiento
- La arquitectura urbana moderna elimina espacios para la contemplación
- El smartphone es una extensión del ruido urbano dentro del hogar
- Las ciudades medievales tenían plazas diseñadas para el silencio
- El silencio es condición necesaria para la creatividad
- El capitalismo de atención explota la incapacidad de estar en silencio
- Las personas en ciudades duermen peor que en zonas rurales
- Movimientos slow-living como respuesta al exceso de ruido
```

---

## 5. Group Ideas

### 5a. Create first group

```vim
:WYTNew g
```

Flow:
1. Telescope picker opens showing all ideas with checkboxes
2. User selects (with `<Tab>` to toggle, `<CR>` to confirm):
   - `El ruido urbano suprime la capacidad de escuchar el propio pensamiento`
   - `La arquitectura urbana moderna elimina espacios para la contemplación`
   - `Las ciudades medievales tenían plazas diseñadas para el silencio`
3. Plugin asks **Suggest group name with LLM?**, again as a *Yes* / *No* menu
4. Either way the name is asked with the guided question for `essay` as the
   prompt: *"¿Cuál es el argumento central que une estas ideas?"*
   - answered *No*, the prompt is empty and you name the group yourself
   - answered *Yes*, the LLM suggestion arrives pre-filled in that same prompt,
     `"El espacio urbano como destructor del silencio"`, ready to accept with
     `<CR>` or edit in place
5. Group is written to plan.wyt.md

**Group section added:**
```markdown
## Grupo: El espacio urbano como destructor del silencio

- El ruido urbano suprime la capacidad de escuchar el propio pensamiento
- La arquitectura urbana moderna elimina espacios para la contemplación
- Las ciudades medievales tenían plazas diseñadas para el silencio
```

Ideas in the Ideas section are automatically tagged:
```markdown
- El ruido urbano suprime la capacidad de escuchar el propio pensamiento [Grupo: El espacio urbano...]
- La arquitectura urbana moderna... [Grupo: El espacio urbano...]
```

### 5b. Create second group

```vim
:WYTNew g
```

Select:
- `El smartphone es una extensión del ruido urbano dentro del hogar`
- `El capitalismo de atención explota la incapacidad de estar en silencio`

Now that a group exists, one extra question comes after the picker: **Add to
existing group or create new?**. Answer **Create new group** and the flow
continues as in 5a.

LLM suggests: `"La economía de la atención como amplificador del ruido"`

### 5c. Create third group

```vim
:WYTNew g
```

Select:
- `El silencio es condición necesaria para la creatividad`
- `Las personas en ciudades duermen peor que en zonas rurales`
- `Movimientos slow-living como respuesta al exceso de ruido`

LLM suggests: `"Recuperar el silencio: salud, creatividad y movimientos alternativos"`

---

## 6. Reorder Groups and Ideas

With `plan.wyt.md` open (the BufEnter autocmd has set up buffer-local keymaps):

### Move a group

Position cursor anywhere inside `## Grupo: La economía de la atención...`:

```
<S-Down>    " move this group one position down
<S-Up>      " move it back up
```

The entire group block (header + all ideas) moves as a unit.

### Move an idea within a group

Position cursor on an idea line inside a group:

```
<S-Down>    " move idea one line down within the group
<S-Up>      " move idea one line up within the group
```

Ideas cannot cross group boundaries.

---

## 7. Implement a Group into a Section

Position cursor on the group header line:

```
## Grupo: El espacio urbano como destructor del silencio
```

Press `<S-Tab>`.

Since this group has no section yet, the plugin asks what the section is *for*,
listing the [archetypes](../USER_GUIDE.md#arquetipos-de-sección) of the project's
type. Pick **Prose (the text itself)** here; §13 covers the others. `<Esc>`
cancels and nothing is created.

What happens automatically:
- Directory `el-espacio-urbano-como-destructor-del-silencio/` is created next to
  the plan that owns it. A section is a plain subdirectory named after the
  group's slug; there is no `sections/` folder anywhere.
- `config.wyt.yml` written: `type` inherited from the project (`essay`),
  `section_kind` and its `content_type` from your answer, and `sections`
  computed from the type's depth
- `plan.wyt.md` created with the group name as its title, an empty Ideas
  section, and one empty `## Grupo:` per idea of the group, so each idea of the
  parent becomes a group of its own waiting to be filled
- Group in root plan is tagged `[Implemented]`
- Auto-commit fires

### 7b. Navigate into the section

Cursor is now on the group header (now `[Implemented]`). Press `<S-Tab>` again.

This time the section exists → `plan.wyt.md` of that section opens in its own
tab. If that file is already open, WYT jumps to its tab instead of opening a
second copy of it.

```
el-espacio-urbano-como-destructor-del-silencio/plan.wyt.md
```

---

## 8. Work on a Section Plan

You are now inside the section's `plan.wyt.md`.

### Add more ideas to this section

```vim
:WYTNew i
```

Guided question now applies at subsection level for `essay`:
*"¿Qué evidencia o ejemplo ilustra mejor esta parte?"*

Add: `Ejemplo de Haussmann demoliendo el Paris medieval para crear bulevares`

### Group section ideas

```vim
:WYTNew g
```

Select the relevant ideas → group them.

### Navigate back to parent plan

Press `<S-Tab>` while cursor is on the title line (`# El espacio urbano...`):

```
# El espacio urbano como destructor del silencio   ← cursor here
```

`<S-Tab>` detects the `#` title → jumps to the parent `plan.wyt.md`, in the tab
that already holds it or in a new one.

---

## 9. Implement Groups to Text

Back in the section's `plan.wyt.md`, position cursor on a group that is ready to write:

```
## Grupo: Las ciudades medievales tenían plazas...
```

Press `<S-Tab>`.

Since `sections: false` in this section's config, the plugin implements to
`text.wyt.md`: the group header is copied over and each of its ideas becomes one
placeholder, the idea itself wrapped in square brackets.

```markdown
## Grupo: Las ciudades medievales tenían plazas...

*Create a paragraph about: [Ejemplo de Haussmann demoliendo el Paris medieval]*

*Create a paragraph about: [Las plazas eran el lugar donde se pensaba en común]*
```

The marker is written in the project's language, so a project still on `lang: es`
gets `*Crea un párrafo sobre: [...]*`. Either form is recognised on expansion and
on export.

A `summary` is the exception: it folds the whole group into a single placeholder
holding every idea separated by `; `. See the
[User Guide](../USER_GUIDE.md#tipos-de-texto).

Group is tagged `[Implemented]` in plan. Auto-commit fires.

---

## 10. Expand Placeholders in text.wyt.md

Navigate to the section's `text.wyt.md`:

```vim
:WYTGoto text
```

Opens `text.wyt.md` in the current section.

The BufEnter autocmd sets buffer-local keymaps for text files.

### Jump to first placeholder and expand

```
]w
```

Cursor jumps to first `*Create a paragraph about: [...]*` placeholder, and the
expansion starts right there. Jumping and expanding are one move.

Plugin prompts **How to expand this placeholder?** with two answers:

- **Generate with LLM** → calls `llm.expand_idea` asynchronously with
  OpenAI/Claude
  - While generating, cursor stays in buffer
  - On completion, the placeholder line is replaced with the generated paragraph
  - The model is asked for the kind of paragraph this type wants, not a generic
    one: *un párrafo argumentativo* for an essay, *un párrafo narrativo* for a
    novel, *un párrafo de notas conciso* for a summary. It is also given the
    project frame, the same one `:WYTGenerate` uses: the type's name, the plan's
    Description, and the title of the plan this placeholder belongs to.
  - A `summary` placeholder holds a whole group's ideas separated by `;`, so
    there the model is told to merge all of them into one paragraph
  - The model is told to reply with prose only, and the reply is stripped of
    headings, code fences and list markers anyway. A `#` heading invented by the
    model would otherwise become a section of the finished export.
- **Write manually** → opens the input panel, titled *Paragraph text*, with the
  idea itself as the question, since a whole idea rarely fits on a prompt line

`<Esc>` at the question leaves the placeholder as it is.

### Expand placeholder at cursor manually

Position cursor on any placeholder:

```
<leader>we    " expand at cursor
```

### Navigate between unexpanded placeholders

```
]w    " jump to next placeholder (and expand it)
[w    " jump to previous placeholder (and expand it)
```

### Expand with explicit command

```vim
:WYTExpand          " expand placeholder at cursor
:WYTExpand next     " find and expand next placeholder
:WYTExpand prev     " find and expand previous placeholder
```

Save after expanding:

```vim
:w
```

Auto-commit fires: `"Save: text.wyt.md"`

---

## 11. Use WYTGenerate

Put the cursor on the blank line between two paragraphs of `text.wyt.md` and
run it with no arguments:

```vim
:WYTGenerate
```

The cursor is the instruction. WYT sends the project frame (type and
description), the group or section heading the cursor sits under, and the
paragraph on either side of it, then asks for a paragraph that carries the
reader from one to the other. The result is inserted where the cursor was.

With the cursor inside a group of `plan.wyt.md` instead, the same command
brainstorms: it sends the ideas already in that group and asks for new ones that
do not repeat them, and inserts them as `- ` ideas rather than as prose.

An argument replaces the default task, and keeps the context:

```vim
:WYTGenerate que sea una sola frase, seca
:WYTGenerate ideas que contradigan las anteriores
```

The [User Guide](../USER_GUIDE.md#cómo-usar-wytgenerate) has the full table of
what is sent from where.

---

## 12. Change Language Mid-Project

```vim
:WYTSetLang en
```

- Updates `localization` module in memory
- Persists `lang: en` to the current project's `config.wyt.yml`
- Auto-commit fires with the config change

All subsequent UI strings, guided questions, and LLM prompts use English.

---

## 13. Reference Sections (archetypes)

Not every section is text you will publish. A novel needs a cast, a chronology
and a list of turning points; an essay needs its key concepts and its sources.
WYT calls these **archetypes**, and the archetype you pick decides three things:
the questions the section asks you from then on, whether it reaches the export,
and whether `:WYTSearch` can see it. The
[User Guide](../USER_GUIDE.md#arquetipos-de-sección) lists them per type.

In the root `plan.wyt.md`, create a group called `Key Concepts`:

```vim
:WYTNew g
```

Select ideas related to definitions → name the group `Key Concepts`.

Position cursor on that group header, press `<S-Tab>` → implement as section.

The section is new, so WYT asks what it is for. Choose
**Key concepts (the terms the argument rests on)**.

The section's `config.wyt.yml` gets `section_kind: key_concepts` and the
`content_type: definition` that archetype implies, while `type` stays the
project's literary type. The answer is asked once, when the section is created:
re-implementing the group later keeps it, and a section created *inside* a
reference section inherits it without asking again.

From now on, `:WYTNew i` inside that section asks "How would you define it in
one sentence?" rather than the essay's argument questions, and `:WYTNew g` asks
"Which concept is this?" instead of asking for an argument name.

### Search across reference sections

From anywhere in the project:

```vim
:WYTSearch
```

WYT reads every reference section, both its `plan.wyt.md` and its
`text.wyt.md`, and lists the lines that match. A reference section is usually
never written into prose at all: its groups are the entries and the ideas under
them are what you know, so most of what you are looking for is in the plan.

Each hit is labelled with the heading it sits under, which is what makes the
result readable. Searching a novel for `afraid`:

```
cast/plan.wyt.md:7 (Ana): - goes quiet when she is afraid
```

`<CR>` jumps to that line in that file. Reference sections are **excluded from
the export** but always searchable, which is the whole point of them: the cast,
the chronology and the turning points are there to be consulted while you write,
not to be published.

---

## 14. Navigate the Full Project Tree

```vim
:WYTNav
```

Opens a Telescope picker showing the hierarchical project tree. Each section is
a directory line, its files indented under it, and the sections come in the
order their groups have in the plan, not in alphabetical order:

```
plan.wyt.md
export.wyt.md
config.wyt.yml
el-espacio-urbano.../
  plan.wyt.md
  text.wyt.md
  config.wyt.yml
la-economia-de-la-atencion.../
  plan.wyt.md
  text.wyt.md
  config.wyt.yml
recuperar-el-silencio.../
  plan.wyt.md
  text.wyt.md
  config.wyt.yml
key-concepts/
  plan.wyt.md
  config.wyt.yml
```

Select any file → opens it in the current window, or jumps to the window that
already shows it. The directory lines are there to read the shape of the
project; selecting one does nothing.

---

## 15. Jump to Specific Files

```vim
:WYTGoto plan      " open current section's plan.wyt.md
:WYTGoto text      " open current section's text.wyt.md
:WYTGoto config    " open current section's config.wyt.yml
:WYTGoto export    " open the root export.wyt.md
:WYTGoto parent    " open the parent section's plan.wyt.md
```

`plan`, `text`, `config` and `parent` are all relative to the **current
section**; only `export` is a root-level file.

`WYTGoto parent` goes up exactly one level, so from a section of this essay it
opens the root `plan.wyt.md`, and from a section nested two deep it opens the
section above it, not the root. From the root it notifies "already at root".

---

## 16. Rename a Group / Section

Rename through `:WYTNew g`, not by editing the header by hand.

```vim
:WYTNew g
```

Pick the ideas as usual, answer **Add to existing group**, choose the group, and
the next prompt is *"Edit group name (leave blank to keep current) [El espacio
urbano como destructor del silencio]:"*. Type the new name there:

```
El espacio urbano y la destrucción del silencio
```

The plugin renames the group in the plan, retags the ideas that belong to it,
and, when the new name slugifies differently, renames the section directory to
match. It says so: `Renamed section folder: el-espacio-urbano-como-... → ...`.

Editing the `## Grupo:` header in the buffer instead only changes the text. The
directory keeps its old name, and the next `<S-Tab>` on that header looks for a
section under the *new* slug, does not find one, and offers to create a second
one. If you have already done it, rename the directory yourself to the slug of
the new name and the two line up again.

---

## 17. Generate the Export

Once all sections have their `text.wyt.md` written:

```vim
:WYTExport
```

The plugin:
1. Reads root `plan.wyt.md` to get section order
2. For each section in order:
   - If `content_type: definition` → skipped, with everything below it
   - Otherwise → uses `text.wyt.md`
   - Strips unexpanded `*Create a paragraph about: [...]*` placeholders, in
     either language
3. Applies the type's [outline map](../USER_GUIDE.md#mapa-de-títulos): a section
   name becomes a heading, a scene break, or nothing, by its plan level
4. Drops the `## Grupo: ...` markers, which are WYT's own structure and not part
   of the finished text, unless the type says group names are headings
5. Writes root `export.wyt.md`
6. Auto-commit fires

The export is assembled, never generated: nothing is sent to the LLM by
`:WYTExport`. What it contains is what you wrote, minus the scaffolding.

For the essay of this walkthrough the result is:

```markdown
# The Silence of Cities

## El espacio urbano como destructor del silencio

Paragraph. Paragraph.

## La economía de la atención como amplificador del ruido

Paragraph.

## Recuperar el silencio: salud, creatividad y movimientos alternativos

Paragraph. Paragraph.
```

Three sections, not four: `key-concepts` carries `content_type: definition`, so
the export leaves it out.

The same project as a `novel` would title its chapters and separate its scenes
with `* * *` instead, and as a `summary` it would turn each group name into a
heading. Nothing about the files changes; only the outline map does.

Open the result:

```vim
:WYTGoto export
```

---

## 18. Reference

The command list, the keymaps, the automatic behaviour, the project types with
their depth and paragraph logic, the outline map and the section archetypes all
live in the [User Guide](../USER_GUIDE.md). They are rules that hold for every
project, so they are documented once there rather than retold here.

---

## 19. Full Project Directory After Completion

```
the-silence-of-cities/
├── config.wyt.yml
├── plan.wyt.md                          ← root plan, all groups [Implemented]
├── export.wyt.md                        ← assembled final text
├── el-espacio-urbano.../
│   ├── config.wyt.yml
│   ├── plan.wyt.md
│   └── text.wyt.md
├── la-economia-de-la-atencion.../
│   ├── config.wyt.yml
│   ├── plan.wyt.md
│   └── text.wyt.md
├── recuperar-el-silencio.../
│   ├── config.wyt.yml
│   ├── plan.wyt.md
│   └── text.wyt.md
└── key-concepts/                        ← definition archetype, excluded from export
    ├── config.wyt.yml
    └── plan.wyt.md
```

Every section is a subdirectory of the plan that owns it, named after the
group's slug. Nesting a level deeper just repeats the shape.

---

## Summary of the Methodological Flow

```
:WYTNew p          → create project + git init
:WYTNew i (×N)    → brainstorm ideas
:WYTNew g (×N)    → group related ideas
<S-Up>/<S-Down>   → reorder groups and ideas
<S-Tab>           → implement group as section
<S-Tab>           → enter section plan
:WYTNew i/g       → refine ideas at section level
<S-Tab>           → implement to text.wyt.md
]w / [w           → expand placeholders (manual or LLM)
:WYTGenerate      → insert free-form AI text
:WYTSearch        → look up definitions while writing
:WYTNav           → browse full project tree
:WYTGoto parent   → return to parent plan
:WYTExport        → assemble final export.wyt.md
```

Every save (`:w`) commits automatically. The user never needs to touch git directly.
