# Tests

```sh
nvim --headless -l tests/runner.lua              # everything
nvim --headless -l tests/runner.lua types llm    # only those specs
```

Exits 1 if anything fails, if a named spec does not exist, or if no spec ran, so
it works from CI or a git hook, from any directory. There is nothing to
install: plenary.nvim is deliberately not a dependency, and the runner provides
the `describe` / `it` / `assert` surface the specs use.

After every `it`, the runner puts back the seams specs stub (`vim.notify`,
`vim.ui.select` and `input`, `vim.health`, `llm.generate_text`,
`ui.edit_file`, `vim.o.columns`, the localization language), so a test that
fails mid-stub cannot change what later specs run against. Stub anything else
and restore it yourself.

## Files

| File | Covers |
|---|---|
| `runner.lua` | the harness, and the only entry point |
| `helpers.lua` | a project on disk, scripted `vim.ui`, a captured LLM prompt |
| `drive.lua` | not a spec: a driven session of the real nvim, see below |
| `config_spec.lua` | the API key's lazy resolve and cache, and the plain resolvers |
| `types_spec.lua` | every text type's guides, depth, outline and archetypes |
| `llm_spec.lua` | every prompt built, and the stripping done to every reply |
| `project_spec.lua` | root resolution, config reads, plan parsing |
| `plan_spec.lua` | the plan-editing helpers |
| `group_spec.lua` | moving groups, naming one, tagging the ideas it claimed |
| `idea_spec.lua` | what the guided brainstorm tells the writer |
| `generate_spec.lua` | what `:WYTGenerate` reads around the cursor, and what it inserts |
| `text_spec.lua` | finding a placeholder and expanding it |
| `export_spec.lua` | the finished document, per type, end to end |
| `tree_spec.lua` | the section walk `:WYTNav` and `:WYTSearch` share |
| `today_spec.lua` | what `:WYTToday` reads from git and the plans, its menu, and a freewrite |
| `place_spec.lua` | where `:WYTPlace` lands each chunk, unchanged, and what stays in the freewrite |
| `outline_spec.lua` | the rows `:WYTOutline` shows, where each opens, and the redraw on save |
| `ui_spec.lua` | fitting text a prompt line would truncate, and opening files |
| `localization_spec.lua` | key parity between the two languages |
| `smoke_spec.lua` | every module loads, every command is registered |

## Writing a spec

Name it `tests/<thing>_spec.lua` and the runner picks it up. Available:
`describe`, `it`, `before_each`, and `assert` with `truthy`, `falsy`, `equals`,
`same`, `is_nil`, `is_not_nil`, `matches`, `has_no_match`. `assert(cond)` still
works as plain Lua.

Two fixtures do most of the work:

```lua
local helpers = require("tests.helpers")

local root = helpers.project({ type = "novel", lang = "es", description = "..." })
-- ... exercise the thing ...
helpers.cleanup(root)
```

```lua
local captured, restore = helpers.capture_prompt("what the model replies")
-- ... call something that generates ...
assert.matches("un párrafo narrativo", captured.prompt)
restore()
```

`helpers.scripted_ui({ answers })` drives `vim.ui.select` and `vim.ui.input` in
order, and `helpers.capture_notify()` keeps `vim.notify` out of the output while
recording what it was told.

## What is not covered

- **The curl transport in `llm.lua`.** Every spec stubs `generate_text`; nothing
  here makes a network call or needs an API key.
- **`secret.lua`'s OS stores.** Keychain, libsecret and DPAPI need the real OS.
  The file, environment and command resolvers are covered.
- **What a floating window looks like.** Headless Neovim does open one, at its
  default 80 columns, so flows that reach a long question really open a panel;
  nothing checks its contents, and the nil fallback is checked by shrinking the
  screen.
- **The guided flows end to end.** The project wizard, `:WYTNew i`, and moving
  or syncing ideas are exercised by hand. Their pieces are covered
  (`types.menu_label`, the prompts they build, the files they write), and
  `group.new_group` is driven through once.

## A driven session

```sh
nvim --headless -u NONE -l tests/drive.lua [out_dir]
```

What the specs leave out above, run for real: your own nvim config (Telescope
draws the menus), the provider behind your API key, the curl transport, and the
floating windows' contents. It builds a project whose prose was committed three
days ago, then types `:WYTToday`, picks the freewrite in the picker, writes and
saves, recaps again, runs `:WYTNav` and `:WYTExport`, places the freewrite with
`:WYTPlace`, and opens a group from `:WYTOutline`. Keys go in through a
terminal; the screen is read back over the child's RPC socket, every window and
float on its tab. Each step's snapshot and `results.txt` land in `out_dir` (a
dated `wyt-drive-*` folder in the system temp directory by default), and it
exits 1 when a check fails.

It needs your nvim config to load WYT and a working API key. It costs a few
model calls, so run it by hand after a change to a flow, not on
every save. Add a step when a bug only showed up driven: that is how the
freewrite text once glued to its prompt was found.

## Landmines these specs were written around

- A section is found through the **group names in its parent's plan**,
  slugified. Creating the folder alone is not enough: the export and the nav
  tree will both skip it.
- A project created inside another project resolves its root to the outer
  config, so `helpers.project` builds each fixture in its own temp directory.
- A file ending in a newline loads one line shorter than the array that wrote
  it, so specs that address a row set the buffer lines directly.
- Windows paths arrive with either separator; normalise both sides before
  comparing.
