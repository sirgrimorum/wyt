# WYT.nvim User Guide

This guide describes the commands, the key mappings and the rules WYT applies
to a project. For a one-page summary, see the [quick guide](./docs/quick_guide.md),
also available as a
[printable page](https://sirgrimorum.github.io/wyt/quick_guide.html).
To see everything in use, start to finish, read the
[full use case](./docs/use_case_e2e.md).

- [Project structure](#project-structure)
- [Commands](#commands)
- [Coming back with :WYTToday](#coming-back-with-wyttoday)
- [Placing a freewrite with :WYTPlace](#placing-a-freewrite-with-wytplace)
- [How to use :WYTGenerate](#how-to-use-wytgenerate)
- [Mappings](#mappings)
- [Automatic behaviour](#automatic-behaviour)
- [Text types](#text-types)
- [Outline map](#outline-map)
- [Section archetypes](#section-archetypes)
- [Example workflow](#example-workflow)

---

## Project structure

A WYT project is plain text files in folders, versioned with git. Nothing is
hidden in a database.

| File | Holds |
|------|-------|
| `config.wyt.yml` | language, text type, archetype, and whether this level nests sub-sections |
| `plan.wyt.md` | the description, the loose ideas and the groups they gather into |
| `text.wyt.md` | the prose, one paragraph per idea, written or generated |
| `export.wyt.md` | the assembled document, rebuilt by `:WYTExport` |
| `freewrite/*.md` | free writing, one file per start, outside the plan until `:WYTPlace` moves it; created at the root |

A **group** is a set of ideas that belong together. `<S-Tab>` on a group header
turns it into a **section** of its own, with its own plan and groups, or writes
it straight into `text.wyt.md` as one placeholder per idea. Which of the two
happens depends on the type's depth, below.

---

## Commands

### Creating things

- `:WYTNew p`
  Creates a new writing project.
  _Follow the interactive prompts: language, type, path, name, root folder,
  content type, sub-sections (only if the type allows more than one level) and
  where to open it. If the root folder already has files, it asks for
  confirmation: every save commits everything in it. If the folder is inside
  another project it asks too: WYT takes the outermost project as the root, so
  the new one would be read as one of its sections._

- `:WYTNew i`
  Adds an idea to the current plan, either free or by answering the type's
  guided questions, one at a time.

- `:WYTNew g`
  Creates a group from the selected ideas of the current plan.

### Configuration

- `:WYTConfig <provider>`
  Sets the LLM provider (`openai` or `claude`) and asks for the API key with no
  echo, outside the history.

- `:WYTSetLang <en|es>`
  Changes the plugin language and saves it in the project's `config.wyt.yml`.
  _It does not rewrite what is already written. WYT only recognises the markers
  of the current language, so in a project with groups the `## Group:` headers
  stop being groups for navigation, search and export. Choose the language when
  you create the project; if you switch, switch back and everything reappears._

### Navigation

- `:WYTNav`
  Picker to move between every file and section of the project.

- `:WYTGoto <plan|config|text|export|parent>`
  Goes straight to the given file:
  - `plan`: `plan.wyt.md` of the current section
  - `config`: `config.wyt.yml` of the current section
  - `text`: `text.wyt.md` of the current section
  - `export`: `export.wyt.md` at the project root
  - `parent`: `plan.wyt.md` of the parent section

- `:WYTSearch`
  Searches the reference sections.

- `:WYTOutline`
  Shows or hides a sidebar of the project, in the order the export walks it:
  each section, the groups written in its text, and, marked `○`, the groups
  its plan names with nothing written yet. The number on a row is what is open
  there: a group counts its placeholders; a section counts everything open in
  it and under it (placeholders, `○` groups, ideas without a group, and its
  sub-sections), so the first row is the whole project. A last row counts
  the freewrites waiting for `:WYTPlace`. `<CR>` opens the row in the window
  beside it, a group at its line; on the freewrite row it opens the newest
  freewrite and runs `:WYTPlace` on it; `p` opens the row's plan; `q` closes.
  A section that holds sub-sections has no groups of its own in the list, its
  sub-sections are its groups, and `<CR>` opens its plan. It redraws when a
  plan, text or freewrite is saved, after `:WYTPlace`, and when you return to
  it.

### Writing and generation

- `:WYTToday`
  The way back into a project: a recap of where you left off, what is still
  open, a prompt for today, and a menu of where to start.
  _See [Coming back with :WYTToday](#coming-back-with-wyttoday)._

- `:WYTPlace`
  Moves the paragraphs of a freewrite to where they belong in the project, one
  chunk at a time, each confirmed by you.
  _See [Placing a freewrite with :WYTPlace](#placing-a-freewrite-with-wytplace)._

- `:WYTGenerate [instruction]`
  Generates at the cursor and inserts the result there.
  _The instruction is optional: without it, the position decides the task. See
  [How to use :WYTGenerate](#how-to-use-wytgenerate)._

- `:WYTExpand`, `:WYTExpand next`, `:WYTExpand prev`
  Expands the paragraph placeholder at the cursor, or finds the next or the
  previous one and expands it.

- `:WYTExport`
  Assembles every section into the root's `export.wyt.md`.

- `:checkhealth wyt`
  Checks dependencies, the LLM provider and where the API key comes from.

`:WYTSearch` reads every section whose archetype makes it reference material,
both its `plan.wyt.md` and its `text.wyt.md`. A Characters section is almost
never written as prose, so most of what you look for is in the plan: the groups
are the entries and the ideas under each are what you know about it. Each
result is labelled with the header it sits under, so a trait tells you whose it
is:

```
cast/plan.wyt.md:7 (Ana): - goes quiet when she is afraid
```

---

## Coming back with :WYTToday

Every save is a commit, so WYT knows where the last session stopped: the last
line changed in the newest commit that touched a `text.wyt.md`. Plan saves do
not count, since a plan is not where the writing stops. The recap grows with the
time away, so that you do not spend your writing time rereading:

| Away | The recap shows |
|------|-----------------|
| under a day | your last paragraph, word for word |
| 1 day to under a week | that paragraph, and a short summary of its scene (its `## Group:` block) |
| a week or more | that paragraph, and a summary of the whole `text.wyt.md` it is in |

The last paragraph is always there word for word: a summary brings back what
happened, but only your own sentence brings back the voice. Below it come the
open items of the content sections (paragraphs to write, groups to implement,
ideas without a group), and one prompt: a question meant to get you writing the
next part right away.

The menu offers, in this order:

- **Continue**: back to the end of that paragraph.
- **Write**: up to two open placeholders. The ones after the last edit, in the
  same file, come first.
- **Freewrite on the prompt**: a new file in `freewrite/`, headed by the prompt
  as a `>` quote, in insert mode. Just **Freewrite**, on a blank file, when the
  model gave no prompt.

A freewrite buffer has no WYT keys and no line numbers, columns or signs: it is
only for typing. It is committed on save like the rest, and a start closed
without a word is deleted. It is not a section, so the export, `:WYTNav` and
`:WYTSearch` leave it alone until `:WYTPlace` moves its paragraphs into one.

The summary and the prompt come from the model, and nothing else in the brief
does. With no API key, or no connection, the brief still opens without them.

## Placing a freewrite with :WYTPlace

Write first, organise after. `:WYTPlace` runs on the freewrite on screen, or
asks which one, newest first. The model groups its paragraphs into chunks and
proposes one home for each:

| Home | What happens to the chunk |
|------|---------------------------|
| After: section › group | added after the last paragraph written in that group |
| New idea in: section › group: idea | added there too, and the idea the model named is added to the plan, under `## Ideas` and under the group |
| Write: idea (section) | replaces that placeholder |
| New group in: section: group › idea | a new `## Group:` holding the chunk, added to the text and claimed in the plan as implemented. In a section with `sections: true` the group is a section of its own instead (`sections: false`, prose, or the archetype of the reference section it sits in) |
| Idea in: section | for a note, not prose: joined into one line, added under the plan's `## Ideas` |
| nowhere yet | stays in the freewrite |

The model names a new idea or group; if the name is taken, nothing moves and
**Change it…** asks for another.

Each chunk is shown in full with its proposed home, one at a time:

- **Place it there**: done, on to the next chunk.
- **Change it…**: type what should change, where it goes or how it is split,
  and the model proposes again for that chunk. An empty answer goes back to the
  menu; `<Esc>` stops.
- **Leave it in freewrite**: on to the next chunk.

`<Esc>` on the menu stops the run; what was placed stays placed. The model only
splits and points: your words are moved as you wrote them, never rewritten.
What was placed leaves the freewrite, and a freewrite left with nothing is
deleted. The run ends in one commit, `"Save: placed freewrite/<file>"`, which
`:WYTToday` reads as writing when a paragraph went into a `text.wyt.md`.

---

## How to use :WYTGenerate

The cursor is not just where the result lands: it is part of the question.
Before calling the model, WYT reads where you are and what is around you, and
builds the prompt from that. You never have to explain the context by hand.

Always sent:

- **The project**: the text type, under its name in your language rather than
  its id, plus the description from `plan.wyt.md`.
- **Where the cursor is**: the nearest header above, section or group, without
  the `Group:` marker or the status tags.
- **What kind of paragraph the type wants**: an essay is asked for an
  argumentative one, a novel for a narrative one, a summary for notes. The
  "Paragraph asked of the model" column in [Text types](#text-types) lists
  them. It does not apply in `plan.wyt.md`: there it asks for ideas, not prose.

Sent depending on the file:

| You are in | Also sent | With no instruction, asks for | Inserted as |
|------------|-----------|-------------------------------|-------------|
| `text.wyt.md`, between two paragraphs | the previous and the next paragraph | a paragraph that leads from one to the other | prose |
| `text.wyt.md`, after the last paragraph | the previous paragraph | the paragraph that follows | prose |
| `plan.wyt.md`, inside a group | the ideas already in that group | new ideas that do not repeat the existing ones | `- ` ideas |
| `plan.wyt.md`, under `## Ideas` | the loose ideas already there | new ideas for the section | `- ` ideas |
| any other file | the previous and the next paragraph | a bridge between them, or the paragraph that follows | prose |

So there are three ways to use it:

**A bridge between paragraphs.** Put the cursor on the blank line between two
paragraphs and run `:WYTGenerate` with no arguments. The model gets both
paragraphs and writes the bridge.

```vim
:WYTGenerate
:WYTGenerate make it a single, dry sentence
```

**Brainstorming in a group or section.** Put the cursor on the group header, or
on any of its ideas, inside `plan.wyt.md`. The model gets the ideas already
there and proposes up to five new ones, inserted as list ideas, not prose.

```vim
:WYTGenerate
:WYTGenerate ideas that contradict the previous ones
```

**Anything else, with an instruction.** The instruction replaces the default
task, but the context is still sent, so you never repeat what the project is
about or which group you are in.

```vim
:WYTGenerate describe the place with three concrete details
:WYTGenerate rewrite the previous paragraph in the third person
```

In a plan, the result always becomes one-line ideas with their `- `, even when
the model answers with a numbered list or with prose. A loose paragraph inside
a `plan.wyt.md` would not be an idea, and the automatic sync would drag it into
every group.

---

## Mappings

> **Note:** every mapping is buffer-local and works in normal mode (`n`), only
> in WYT files. They do not override your keys in any other buffer.

| Key | File | Action |
|-----|------|--------|
| `<S-Tab>` | `plan.wyt.md` | Context navigation: implement the group as a section, enter the section, or go back to the parent plan |
| `<S-Up>` | `plan.wyt.md` | Moves the current idea or group up |
| `<S-Down>` | `plan.wyt.md` | Moves the current idea or group down |
| `<leader>we` | `text.wyt.md` | Expands the placeholder at the cursor |
| `]w` | `text.wyt.md` | Jumps to the next placeholder and expands it |
| `[w` | `text.wyt.md` | Jumps to the previous placeholder and expands it |

Every WYT navigation, by mapping or by command, does two things before moving:
it saves the current file if it has unwritten changes, which also fires the
automatic commit, and it looks for a window already showing the destination. So
no work is lost in a jump, and going back and forth between a plan and its
section reuses the two tabs instead of piling up copies.

---

## Automatic behaviour

This happens on its own, with nothing to run:

| Trigger | File | Effect |
|---------|------|--------|
| `BufEnter` | `plan.wyt.md` | Reads the language from the config, applies it and sets the buffer mappings |
| `BufEnter` | `text.wyt.md` | The same, with the text mappings |
| `TextChanged`, `InsertLeave` | `*plan.wyt.md` | Syncs after a 300 ms wait: the ideas in the groups are mirrored in the `## Ideas` section |
| `BufWritePost` | `*plan.wyt.md` | Automatic commit: `"Save: plan.wyt.md"`; an open `:WYTOutline` redraws |
| `BufWritePost` | `*text.wyt.md` | Automatic commit: `"Save: text.wyt.md"`; an open `:WYTOutline` redraws |
| `BufEnter` | `freewrite/*.md` | Bare buffer: wrap at words, no numbers, signs or columns |
| `BufWritePost` | `freewrite/*.md` | Automatic commit: `"Save: freewrite/<file>"`; an open `:WYTOutline` redraws |
| `BufUnload` | `freewrite/*.md` | Deletes the file when it still holds only the prompt |

Every save commits, so the project's history is the history of the writing. You
never need to touch git by hand.

Text the model returns is cleaned before it enters a file: headings, code
blocks and list markers are removed. A `#` invented by the model would be read
as structure and end up as a section of the export.

---

## Text types

| Name in the menu | Type | Guided questions | Paragraph asked of the model | Paragraph logic | Max depth |
|---|---|---|---|---|---|
| Novel | `novel` | Arc, character, scene | A narrative paragraph | 1 idea → 1 paragraph | 3 levels |
| Long novel | `long_novel` | Main thread, part, subplot, chronology | A narrative paragraph | 1 idea → 1 paragraph | 4 levels |
| Short novel | `short_novel` | Scene, desire, consequence | A narrative paragraph | 1 idea → 1 paragraph | 2 levels |
| Short story | `short_story` | Narrative focus, tone | A literary paragraph | 1 idea → 1 paragraph | 1 level |
| Essay | `essay` | Argument, evidence, perspective | An argumentative paragraph | 1 idea → 1 paragraph | 2 levels |
| Summary | `summary` | Key point, synthesis | A concise paragraph of notes | Several ideas → 1 paragraph | 1 level |

**Name in the menu** is what you see when you create the project, next to a
line saying what that type does to the final text. The **type** in the second
column is the id stored in `config.wyt.yml`; it never appears on screen.

**Guided questions** is the second mode of `:WYTNew i`. They come one at a
time and each answer becomes an idea. The type decides which they are, and a
section's archetype can replace them with its own.

**Paragraph asked of the model** is what changes in the prompt when you expand
a placeholder or use `:WYTGenerate`: an essay is asked for an argumentative
paragraph and a novel for a narrative one. The model is also given the type's
name in your language, never the id: *Long novel*, not `long_novel`.

**Max depth** counts plan levels, the root plan being level 1. A section
created with `<S-Tab>` gets `sections: true` while it is below the limit, so
its own groups become sections in turn; at the limit it gets `sections: false`
and its groups go straight to `text.wyt.md`. So an `essay` nests one level of
sections under the root, a `novel` two, a `long_novel` three, and `short_story`
and `summary` none: their groups go straight to the text. The wizard only asks
"Will the main section have sub-sections?" for types that allow more than one
level.

**Paragraph logic** decides what `<S-Tab>` writes into `text.wyt.md`. Every
type except `summary` writes one placeholder per idea. `summary` condenses: the
whole group becomes a single placeholder holding all its ideas separated by
`;`, and expanding it gives one paragraph that merges them.

### Taking one branch a level deeper

The type's depth is only the default **at creation**. What actually governs a
section is its own `sections:`, and you can edit that switch by hand. If one
branch needs a level more than its type hands out, open that section's
`config.wyt.yml` and set `sections: true`:

```yaml
type: essay
section_kind: prose
content_type: definition
sections: true    # this section nests, even though the essay was at its limit
```

From then on, `<S-Tab>` on a group of that section creates a sub-section
instead of sending the group to `text.wyt.md`. The change is **local to that
branch**: its sibling sections keep `sections: false` and keep writing text,
and the new sub-sections are created with the value their type gives them, so
the tree does not run away on its own. There is no global depth key, and none
is needed: for an essay you want entirely in three levels, the type is the
right place.

Two details worth knowing:

- The switch only decides what happens **from then on**. Setting it to `false`
  on a section that already has sub-sections does not delete them or drop them
  from the export; it only makes the next `<S-Tab>` write text instead of
  creating another.
- The [outline map](#outline-map) only declares levels up to the type's own
  depth. An extra level gets no title: its blocks simply follow one another,
  separated by a blank line, inside the title of the level that is declared.
  The export does not break, but it does not title either. If you want titles
  there, the type is where to declare them.

---

## Outline map

The same names, placed the same way, compose differently depending on the
form: an essay titles its sections, a novel titles its chapters but never its
scenes. Each type declares what a name at a given level becomes when the export
is built.

| Type | level 2 | level 3 | level 4 | groups inside `text.wyt.md` |
|------|---------|---------|---------|-----------------------------|
| `novel` | chapter `##` | scene: `* * *` | - | nothing |
| `long_novel` | part `##` | chapter `###` | scene: `* * *` | nothing |
| `short_novel` | scene: `* * *` | - | - | nothing |
| `short_story` | - | - | - | scene: `* * *` |
| `essay` | section `##` | - | - | nothing |
| `summary` | - | - | - | `##` per group |

The root is always the document title, so no type declares level 1. "Nothing"
means the blocks simply follow, separated by a blank line: the paragraphs of an
essay do not want a title each, and neither do those of a novel.

The `## Group: ...` lines inside `text.wyt.md` are WYT's own markers, put there
so a group can be found again when it is re-implemented. In the export they are
resolved with this map, not copied into the document. Unexpanded placeholders
are dropped too: a note you wrote to yourself is not part of the text.

The same project, assembled as three different types:

```
ESSAY                                NOVEL                                  SUMMARY
# The silence of cities              # Nightfall                            # Meeting notes

## Urban space                       ## Chapter one                         ## What was decided

The city hums before dawn.           The gate had gone years without oil.   The launch moves to March.

The squares held their breath.       * * *                                  ## What is still open

## The attention economy             She arrived three winters late.        Nobody has taken it on.

The street now rings at the table.   ## Chapter two
```

---

## Section archetypes

An archetype says what a section is for. It is asked once, when `<S-Tab>`
creates the section, and from then on it decides three things: that section's
guided questions, whether it reaches the export, and whether `:WYTSearch` sees
it.

| Archetype | For | Exported |
|-----------|-----|----------|
| Prose | the text itself; guided by the project's type | yes |
| Characters | one group per character: want, need, wound, voice | no, but searchable |
| Setting | the places and the rules of the world | no, but searchable |
| Chronology | when each thing happens, in story order | no, but searchable |
| Turning points | what changes everything, and what it costs | no, but searchable |
| Themes | what the work is about underneath | no, but searchable |
| Key concepts | the terms the argument rests on | no, but searchable |
| Sources | the evidence you cite | no, but searchable |
| Counterarguments | the objections the essay answers | yes |

Which ones are offered depends on the type:

| Type | Archetypes offered |
|------|--------------------|
| `novel`, `long_novel`, `short_novel`, `short_story` | Prose, Characters, Setting, Chronology, Turning points, Themes |
| `essay` | Prose, Key concepts, Sources, Counterarguments, Themes |
| `summary` | Prose, Key concepts, Sources |

A reference section is worked like any other: its groups are the entries (a
character, a concept, a date) and the ideas under each are what you know. If
you give a character a section of their own, it inherits the archetype without
asking again, because a section of a Characters section is still about
characters.

Counterarguments is the only reference-shaped archetype that is exported: the
objections are written into the essay, not just collected.

---

## Example workflow

```
:WYTNew p          create the project and its git repository
:WYTNew i (×N)     gather ideas, free or with the type's questions
:WYTNew g (×N)     group the ideas that belong together
<S-Up>/<S-Down>    order groups and ideas
<S-Tab>            turn a group into a section, or into text
<S-Tab>            enter the section and refine it with :WYTNew i/g
]w  [w             expand the placeholders into paragraphs
:WYTGenerate       insert generated text where it is needed
:WYTSearch         look up characters, chronology or concepts while writing
:WYTNav            walk the project tree
:WYTGoto parent    go back to the parent plan
:WYTExport         assemble the final export
```

---

## Requirements

- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) installed
  and configured.

Questions or suggestions? See the [README](./README.md) or open an issue in the
repository.
