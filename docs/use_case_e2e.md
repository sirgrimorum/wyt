# WYT — End-to-End Use Case

A complete walkthrough of the WYT methodology using every command, keymap, and option.
The example project is a **short essay** titled *"The Silence of Cities"*.

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

Before using AI-assisted features, set your provider and API key:

```vim
:WYTConfig openai sk-proj-...your-key...
" or
:WYTConfig claude sk-ant-...your-key...
```

This saves the provider and key to the global plugin config. Only needs to be done once per Neovim session (or persisted via your own config).

---

## 2. Create a New Project

```vim
:WYTNew p
```

Interactive wizard prompts:

| Prompt | Example answer |
|--------|----------------|
| Language | `es` |
| Text type | `essay` |
| Path | `/home/user/writing` (pre-filled with the current directory) |
| Project name | `The Silence of Cities` |
| Root folder name | `the-silence-of-cities` (pre-filled with the slug; `.` = use the path itself) |
| Content type | `content` |
| Has sections? | `y` |
| Open in | `Same window` |

The text types offered are `novel`, `long_novel`, `short_novel`, `short_story`,
`essay` and `summary`. **Has sections?** is only asked for a type that allows
more than one plan level (see §21): `short_story` and `summary` are
single-level, so the wizard writes `sections: false` without asking.

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
4. Plugin asks: **Improve with LLM? [y/N]**
5. User types `y`. The refined sentence appears in full in a panel titled
   *Idea mejorada* above the menu, and the menu decides what happens to it. The
   result is never applied on its own:

   | Option | Effect |
   |--------|--------|
   | Keep this version | store the generated sentence |
   | Edit this version | open it in an input, pre-filled, to adjust |
   | Generate another | ask again for a clearly different version |
   | Keep my original | discard the generation, store what you typed |

   `<Esc>` is the same as *Keep my original*.
6. Plugin asks: **Add to group? [y/N]**  — User types `n` (no group yet)
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
3. Plugin asks: **Suggest group name with LLM? [y/N]**
4. Either way the name is asked with the guided question for `essay` as the
   prompt: *"¿Cuál es el argumento central que une estas ideas?"*
   - answered `n`, the prompt is empty and you name the group yourself
   - answered `y`, the LLM suggestion arrives pre-filled in that same prompt,
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
listing the archetypes of the project's type (§21b). Pick **Prose (the text
itself)** here; §13 covers the others. `<Esc>` cancels and nothing is created.

What happens automatically:
- Directory `sections/el-espacio-urbano-como-destructor-del-silencio/` is created
- `config.wyt.yml` written: `type` inherited from the project (`essay`),
  `section_kind` and its `content_type` from your answer, and `sections`
  computed from the type's depth
- `plan.wyt.md` created with:
  - Title = group name
  - Description = ideas from the group (joined as description text)
  - Each idea from the group becomes a `## Grupo: [idea]` with sub-ideas pre-populated
- Group in root plan is tagged `[Implemented]`
- Auto-commit fires

### 7b. Navigate into the section

Cursor is now on the group header (now `[Implemented]`). Press `<S-Tab>` again.

This time the section exists → `plan.wyt.md` of that section opens in its own
tab. If that file is already open, WYT jumps to its tab instead of opening a
second copy of it.

```
sections/el-espacio-urbano-como-destructor-del-silencio/plan.wyt.md
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

Since `sections: false` in this section's config, the plugin implements to `text.wyt.md`:
- `text.wyt.md` is created/updated with group header and one placeholder per idea:

```markdown
## El espacio urbano como destructor del silencio

*Create a paragraph about: El ruido urbano suprime la capacidad...*

*Create a paragraph about: La arquitectura urbana moderna elimina espacios...*

*Create a paragraph about: Las ciudades medievales tenían plazas...*
```

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

Cursor jumps to first `*Create a paragraph about: ...*` placeholder.

Plugin prompts: **Expand with LLM or manual? [l/m]**

- `l` → calls `llm.expand_idea(idea_text, context, lang, callback)` asynchronously with OpenAI/Claude
  - While generating, cursor stays in buffer
  - On completion, placeholder is replaced with generated paragraph
  - The model is told to reply with prose only, and the reply is stripped of
    headings, code fences and list markers anyway. A `#` heading invented by the
    model would otherwise become a section of the finished export.
- `m` → opens a small input prompt, user types the paragraph manually

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

## 11. Use WYTGenerate for Free-Form Text

With `text.wyt.md` open and cursor positioned where you want to insert text:

```vim
:WYTGenerate escribe una transición entre los dos párrafos anteriores
```

The LLM is called asynchronously with your prompt + project context (description, type, language). Generated text is inserted at cursor position when ready.

```vim
:WYTGenerate    " without arguments → uses a default creative prompt
```

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
and whether `:WYTSearch` can see it. §21b lists the archetypes per type.

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

### Search across definition sections

From anywhere in the project:

```vim
:WYTSearch
```

A Telescope picker opens with all content from `definition`-type sections.
Type to filter → `<CR>` to jump to the matching line in the relevant file.

Definition sections are **excluded from export** but always searchable.

---

## 14. Navigate the Full Project Tree

```vim
:WYTNav
```

Opens a Telescope picker showing the hierarchical project tree, indented by depth:

```
plan.wyt.md
  sections/el-espacio-urbano.../plan.wyt.md
  sections/el-espacio-urbano.../text.wyt.md
  sections/la-economia-de-la-atencion.../plan.wyt.md
  sections/la-economia-de-la-atencion.../text.wyt.md
  sections/recuperar-el-silencio.../plan.wyt.md
  sections/recuperar-el-silencio.../text.wyt.md
  sections/key-concepts.../plan.wyt.md
export.wyt.md
config.wyt.yml
```

Select any entry → opens that file in the current window, or jumps to the
window that already shows it.

---

## 15. Jump to Specific Files

```vim
:WYTGoto plan      " open current section's plan.wyt.md
:WYTGoto text      " open current section's text.wyt.md
:WYTGoto config    " open current section's config.wyt.yml
:WYTGoto export    " open the root export.wyt.md
:WYTGoto parent    " open the parent section's plan.wyt.md
```

`WYTGoto parent` from inside a section → opens root `plan.wyt.md`.
`WYTGoto parent` from root → notifies "already at root".

---

## 16. Rename a Group / Section

In `plan.wyt.md`, edit the group header text directly:

```markdown
## Grupo: El espacio urbano como destructor del silencio
" →
## Grupo: El espacio urbano y la destrucción del silencio
```

Save (`:w`).

The auto-commit fires. On next `<S-Tab>` navigation to this group, the plugin detects the folder name mismatch and renames the `sections/` folder to the new slug automatically.

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
   - Strips unexpanded `*Create a paragraph about: ...*` placeholders
3. Applies the type's outline map (§21): a section name becomes a heading, a
   scene break, or nothing, according to its plan level
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
```

The same project as a `novel` would title its chapters and separate its scenes
with `* * *` instead, and as a `summary` it would turn each group name into a
heading. Nothing about the files changes; only the outline map does.

Open the result:

```vim
:WYTGoto export
```

---

## 18. Full Command Reference

| Command | Description |
|---------|-------------|
| `:WYTNew p` | Create new project (wizard) |
| `:WYTNew i` | Add a new idea to current plan |
| `:WYTNew g` | Create a group from selected ideas |
| `:WYTConfig <provider> <key>` | Set LLM provider and API key |
| `:WYTSetLang <en\|es>` | Change language (persists to config) |
| `:WYTNav` | Hierarchical project file browser |
| `:WYTGoto <plan\|config\|text\|export\|parent>` | Jump to project file |
| `:WYTGenerate [prompt]` | Insert LLM-generated text at cursor |
| `:WYTExpand` | Expand placeholder at cursor |
| `:WYTExpand next` | Find and expand next placeholder |
| `:WYTExpand prev` | Find and expand previous placeholder |
| `:WYTSearch` | Search across definition sections |
| `:WYTExport` | Assemble all sections into export.wyt.md |
| `:checkhealth wyt` | Verify plugin dependencies |

---

## 19. Full Keymap Reference

| Key | Buffer | Action |
|-----|--------|--------|
| `<S-Tab>` | `plan.wyt.md` | Context-aware navigation: implement group → section, navigate to section, navigate to parent plan |
| `<S-Up>` | `plan.wyt.md` | Move current idea or entire group up |
| `<S-Down>` | `plan.wyt.md` | Move current idea or entire group down |
| `<leader>we` | `text.wyt.md` | Expand placeholder at cursor |
| `]w` | `text.wyt.md` | Jump to next placeholder and expand |
| `[w` | `text.wyt.md` | Jump to previous placeholder and expand |

All keymaps are **buffer-local** — they only activate in WYT files and do not override keys in other buffers.

Every WYT navigation, by keymap or by command, does two things first: it writes
the current file if it has unsaved changes, which also fires the auto-commit, and
it looks for a window that already shows the target. So work is never lost to a
move, and moving back and forth between a plan and its section reuses the two
tabs instead of piling up copies.

---

## 20. Autocmd Behaviors (Transparent)

These fire automatically without user action:

| Trigger | File | Effect |
|---------|------|--------|
| `BufEnter` | `plan.wyt.md` | Reads project lang from config, applies to localization, sets buffer-local keymaps |
| `BufEnter` | `text.wyt.md` | Same as above, sets text-file keymaps |
| `TextChanged`, `InsertLeave` | `*plan.wyt.md` | Debounced 300ms sync: ideas in groups are mirrored to `## Ideas` section |
| `BufWritePost` | `*plan.wyt.md` | Auto git commit: `"Save: plan.wyt.md"` |
| `BufWritePost` | `*text.wyt.md` | Auto git commit: `"Save: text.wyt.md"` |

---

## 21. Supported Project Types

| Type | Guided questions | Paragraph logic | Max depth |
|------|-----------------|-----------------|-----------|
| `novel` | Story-arc, character, scene questions | 1 idea → 1 paragraph | 3 levels |
| `long_novel` | Through-line, part, subplot, timeline questions | 1 idea → 1 paragraph | 4 levels |
| `short_novel` | Scene, want, consequence questions | 1 idea → 1 paragraph | 2 levels |
| `short_story` | Narrative focus, tone questions | 1 idea → 1 paragraph | 1 level |
| `essay` | Argument, evidence, perspective questions | 1 idea → 1 paragraph | 2 levels |
| `summary` | Key point, synthesis questions | Multiple ideas → 1 paragraph | 1 level |

**Max depth** counts plan levels, the root plan being level 1. A section created
with `<S-Tab>` gets `sections: true` while it is still above the limit, so its
own groups become sections in turn; at the limit it gets `sections: false` and
its groups implement straight to `text.wyt.md`. An `essay` therefore nests one
level of sections under the root, a `novel` two, a `long_novel` three, and
`short_story` and `summary` none: their groups go straight to text.

**Paragraph logic** decides what `<S-Tab>` writes into `text.wyt.md`. Every type
but `summary` writes one placeholder per idea. `summary` condenses, so a group
becomes a single placeholder listing all of its ideas, separated by `;`, and
expanding it produces one paragraph that folds them together.

### Outline map

The same names, placed the same way, are set differently by each form. Each type
declares what a name at a given plan level becomes in the export:

| Type | level 2 | level 3 | level 4 | groups inside `text.wyt.md` |
|------|---------|---------|---------|------------------------------|
| `novel` | chapter `##` | scene: `* * *` | — | nothing |
| `long_novel` | part `##` | chapter `###` | scene: `* * *` | nothing |
| `short_novel` | scene: `* * *` | — | — | nothing |
| `short_story` | — | — | — | scene: `* * *` |
| `essay` | section `##` | — | — | nothing |
| `summary` | — | — | — | `##` per group |

The root is always the document title, so no type declares level 1. "Nothing"
means the blocks simply run on, separated by a blank line: an essay's paragraphs
do not each want a title, and neither do a novel's.

---

## 21b. Section Archetypes

An archetype says what a section is *for*. It is asked once, when `<S-Tab>`
creates the section, and from then on it supplies that section's guided
questions, decides whether the section reaches the export, and decides whether
`:WYTSearch` can see it.

| Archetype | For | Exported |
|-----------|-----|----------|
| Prose | the text itself; guided by the project type | yes |
| Characters | one group per character: want, need, wound, voice | no, searchable |
| Setting | places and the rules of the world | no, searchable |
| Chronology | when things happen, in story order rather than narrative order | no, searchable |
| Turning points | what changes everything, and what it costs | no, searchable |
| Themes | what the work is about underneath | no, searchable |
| Key concepts | the terms an argument rests on | no, searchable |
| Sources | the evidence being cited | no, searchable |
| Counterarguments | the objections the essay answers | yes |

Which are offered depends on the type:

| Type | Archetypes offered |
|------|--------------------|
| `novel`, `long_novel`, `short_novel`, `short_story` | Prose, Characters, Setting, Chronology, Turning points, Themes |
| `essay` | Prose, Key concepts, Sources, Counterarguments, Themes |
| `summary` | Prose, Key concepts, Sources |

A section created inside a reference section inherits its archetype without
asking: a section of a Characters section is still about characters.

---

## 22. Full Project Directory After Completion

```
the-silence-of-cities/
├── config.wyt.yml
├── plan.wyt.md                          ← root plan, all groups [Implemented]
├── export.wyt.md                        ← assembled final text
└── sections/
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
    └── key-concepts/                    ← definition type, excluded from export
        ├── config.wyt.yml
        └── plan.wyt.md
```

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
