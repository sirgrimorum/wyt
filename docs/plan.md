# WYT Plugin — Code Review Plan

Based on code review of all Lua files and cross-referenced against:
- `docs/metodologia.txt` — the methodology specification
- `docs/nvim-lua-best-practices.md` — community patterns

---

## 1. FIXES (Bugs)

### F1 — Undefined variables in `set_section_data()` (crash bug)
**File:** `lua/wyt/project.lua:88-89`

`config_path` and `plan_path` are referenced as bare names but they are not in scope. They were likely meant to be `M.config_path` and `M.plan_path` as fallbacks.

```lua
-- BUG
M.section_config_path = config_path   -- NameError: config_path is nil
M.section_plan_path = plan_path       -- NameError: plan_path is nil

-- FIX
M.section_config_path = M.config_path
M.section_plan_path = M.plan_path
```

---

### F2 — Stale project root cache when switching between projects
**File:** `lua/wyt/project.lua:66-69`

`set_root_data()` returns early if `M.project_root` is already set, so switching to a different WYT project in the same Neovim session reuses the wrong root.

```lua
-- BUG: early return prevents re-detection
function set_root_data()
    if M.project_root ~= "" and M.config_path ~= "" and M.plan_path ~= "" then
        return true   -- always uses first project found
    end
    ...
end

-- FIX: always re-detect from current buffer
local function set_root_data()
    M.project_root = find_project_root_from_buffer()
    ...
end
```

---

### F3 — Undeclared global variable `col`
**File:** `lua/wyt/plan.lua:145`

`col` is assigned without `local`, leaking it into the global namespace and potentially conflicting with other plugins.

```lua
-- BUG
col = api.nvim_win_get_cursor(0)[2] + 1

-- FIX
local col = api.nvim_win_get_cursor(0)[2] + 1
```

---

### F4 — No augroup in autocmds, duplicated on re-setup
**File:** `lua/wyt/autocmd.lua`

Autocmds are registered with no augroup. If `setup()` is called more than once (e.g. user re-sources config), every autocmd is duplicated.

```lua
-- FIX: wrap in a named augroup
local group = vim.api.nvim_create_augroup("WYT", { clear = true })
vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    pattern = "plan.wyt.md",
    ...
})
```

---

### F5 — Path injection via unescaped `vim.cmd("e " .. path)`
**Files:** `lua/wyt/commands.lua:95,139` · `lua/wyt/project.lua:178-179` · `lua/wyt/group.lua:180` · `lua/wyt/plan.lua:54,94,109,158`

Filenames with spaces or special characters break the command. This is also a security issue if paths come from user input.

```lua
-- BUG
vim.cmd("e " .. root .. choice)
vim.cmd("tabnew " .. section_plan)

-- FIX — use fnameescape() or the API form
vim.cmd.edit(vim.fn.fnameescape(path))
vim.cmd.tabnew(vim.fn.fnameescape(path))
-- or Neovim 0.10+:
vim.cmd({ cmd = "edit", args = { path } })
```

---

### F6 — Double slash in text path
**File:** `lua/wyt/plan.lua:96`

`current_section_dir` already ends with `/` (from `get_section_dir()`), so this creates `dir//text.wyt.md`.

```lua
-- BUG
local text_path = current_section_dir .. "/text.wyt.md"

-- FIX
local text_path = current_section_dir .. "text.wyt.md"
```

---

### F7 — `write_file` crashes on unwritable paths
**File:** `lua/wyt/project.lua:49`

`assert(uv.fs_open(...))` raises an uncaught Lua error if the path is unwritable (wrong permissions, non-existent parent, etc.).

```lua
-- BUG
local fd = assert(uv.fs_open(path, "w", 438))

-- FIX
function M.write_file(path, content)
    local fd = uv.fs_open(path, "w", 438)
    if not fd then
        vim.notify("[WYT] Cannot write to: " .. path, vim.log.levels.ERROR)
        return false
    end
    uv.fs_write(fd, content, -1)
    uv.fs_close(fd)
    return true
end
```

---

### F8 — Global keymaps hijack keys in every buffer
**File:** `lua/wyt/mappings.lua:29-31`

`<S-Up>`, `<S-Down>`, and `<S-Tab>` are set as global normal-mode mappings. They override these keys in every buffer in the session.

```lua
-- BUG — global, active everywhere
vim.keymap.set("n", "<S-Tab>", plan.goto_wyt_tab, {...})

-- FIX — buffer-local via BufEnter autocmd in autocmd.lua
vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    pattern = "*plan.wyt.md",
    callback = function(ev)
        local buf = ev.buf
        vim.keymap.set("n", "<S-Tab>", plan.goto_wyt_tab, {
            buffer = buf, desc = "WYT: navigate to tab"
        })
        vim.keymap.set("n", "<S-Up>", function() handle_move("up") end, {
            buffer = buf, desc = "WYT: move up"
        })
        vim.keymap.set("n", "<S-Down>", function() handle_move("down") end, {
            buffer = buf, desc = "WYT: move down"
        })
    end,
})
```

---

### F9 — Language from config never applied to `localization` module
**Files:** `lua/wyt/autocmd.lua:23` · `lua/wyt/localization.lua`

The BufEnter autocmd reads the project language but has `loc.set_lang(lang)` commented out. As a result, `loc.t()` called from any module without an explicit `lang` argument always uses the global default (`"en"`), ignoring the project's `config.wyt.yml` language setting.

```lua
-- FIX in autocmd.lua — uncomment and apply
callback = function()
    if not project.setup() then return end
    loc.set_lang(project.lang)   -- sync localization module with project lang
end,
```

Also, `project.t(key)` passes `M.lang` to `loc.t()`, which works for calls through `project.t()`, but all direct `loc.t()` calls in other modules ignore project language.

---

### F10 — `add_item_to_section` conflates translation keys with raw strings
**File:** `lua/wyt/plan.lua:169`

The `section` parameter is sometimes a translation key (`"ideas_section"`) and sometimes a pre-translated string (`"Group: My Group"`). The function blindly calls `project.t(section)`, which works for the pre-translated case only because `loc.t()` returns the key itself on a miss — a fragile coincidence.

```lua
-- Confusing call sites:
plan.add_item_to_section(content, "ideas_section", idea)           -- key
plan.add_item_to_section(content, project.t("group_tag") .. ": " .. name, idea) -- pre-translated

-- FIX: accept the final header text directly; callers translate
function M.add_item_to_section(content, section_header_text, item)
    local section_header = "## " .. section_header_text
    ...
end
-- Then callers always pass translated text:
plan.add_item_to_section(content, project.t("ideas_section"), idea)
plan.add_item_to_section(content, project.t("group_tag") .. ": " .. name, idea)
```

---

### F11 — `helper functions` in `project.lua` not declared `local`
**File:** `lua/wyt/project.lua:66,82`

`set_root_data` and `set_section_data` are defined without `local`, making them global functions that any code in the session can accidentally call or overwrite.

```lua
-- BUG
function set_root_data() ... end
function set_section_data() ... end

-- FIX
local function set_root_data() ... end
local function set_section_data() ... end
```

---

### F12 — Telescope required at module load time in `idea.lua`
**File:** `lua/wyt/idea.lua:19`

`local multi_select = require("wyt.group").multi_select` runs at module load, not inside a function. If telescope is not installed, loading `idea` crashes immediately.

```lua
-- BUG — top-level side effect
local multi_select = require("wyt.group").multi_select

-- FIX — inline at use site
local function multi_select(...)
    return require("wyt.group").multi_select(...)
end
```

---

### F13 — `WYTNav` does not escape the path before `vim.cmd("e " ...)`
**File:** `lua/wyt/commands.lua:95`

Beyond the injection bug (F5), the navigator currently allows opening the currently-active file by stripping the `"→ "` prefix only for the arrow case, but still allows re-opening it. Minor UX issue worth fixing while touching the function.

---

## 2. OPTIMIZATIONS

### O1 — Eager requires in `commands.lua`
**File:** `lua/wyt/commands.lua:1-6`

All six modules are required at the top of `commands.lua`, loading them all at startup (when `commands.setup()` is called from `init.lua`). Move requires inside callback closures.

```lua
-- BAD — all loaded at startup
local config = require("wyt.config")
local llm = require("wyt.llm")
local project = require("wyt.project")
...

-- GOOD — loaded on first command use
vim.api.nvim_create_user_command("WYTConfig", function(args)
    local config = require("wyt.config")
    local loc = require("wyt.localization")
    ...
end, {...})
```

---

### O2 — Use `vim.uv` instead of deprecated `vim.loop`
**File:** `lua/wyt/project.lua:1`

`vim.loop` is deprecated since Neovim 0.10. Replace with `vim.uv`.

```lua
-- BUG/deprecation
local uv = vim.loop

-- FIX
local uv = vim.uv
```

---

### O3 — Debounce `sync_group_ideas_to_ideas` on TextChanged
**File:** `lua/wyt/autocmd.lua:29-33`

The sync function runs on every keystroke (`TextChanged`, `TextChangedP`, `InsertLeave`). It reads all buffer lines, builds multiple tables, and calls `nvim_buf_set_lines`. Add a debounce to avoid repeated work during active typing.

```lua
-- See nvim-lua-best-practices.md §14 for debounce implementation
callback = debounce(idea.sync_group_ideas_to_ideas, 300),
```

---

### O4 — Replace `vim.fn.filereadable()` with `vim.uv.fs_stat()`
**Throughout project.lua, plan.lua, group.lua**

`vim.fn.filereadable()` calls into Vimscript. `vim.uv.fs_stat()` is faster and Lua-native.

```lua
-- BAD
if vim.fn.filereadable(path) == 1 then

-- GOOD
if vim.uv.fs_stat(path) then
```

---

### O5 — `vim.tbl_extend` should be `vim.tbl_deep_extend` in config
**File:** `lua/wyt/config.lua:9`

`vim.tbl_extend` is a shallow merge. If nested config tables are ever added, user values would replace entire sub-tables. Use `deep_extend` for correctness.

```lua
-- BUG
M.options = vim.tbl_extend("force", M.options, opts or {})

-- FIX
M.options = vim.tbl_deep_extend("force", M.options, opts or {})
```

---

### O6 — Emit `vim.notify` instead of `print` everywhere
**Throughout all files**

`print()` writes to the Neovim command line but is not compatible with notification plugins (nvim-notify, snacks.nvim, etc.) and has no severity level.

```lua
-- BAD
print(loc.t("project_created") .. root)
print("[WYT] Language set to: " .. lang)

-- GOOD
vim.notify(loc.t("project_created") .. root, vim.log.levels.INFO, { title = "WYT" })
```

---

### O7 — `vim.cmd("write")` in `group.new_group` is surprising
**File:** `lua/wyt/group.lua:141`

Silently force-saving the buffer when the user runs `:WYTNew g` is unexpected behavior and can overwrite unsaved changes. Instead, read from the buffer lines directly, or prompt the user.

---

### O8 — Deduplicate block-swap logic in `move_group`
**File:** `lua/wyt/group.lua:296-351`

The "up" and "down" cases of `move_group` duplicate the entire block-swap algorithm (building `new_lines` by iterating all lines). Extract into a shared helper.

```lua
local function swap_blocks(lines, a_start, a_end, b_start, b_end)
    -- returns new lines with blocks at a and b swapped
end
```

---

### O9 — Add a `plugin/` directory with thin entry point
Currently there is no `plugin/wyt.lua`. All setup runs from `lua/wyt/init.lua` which users call manually. A `plugin/` file would allow zero-config auto-setup (opt-in), following standard plugin conventions.

---

### O10 — Cache project root per buffer
**File:** `lua/wyt/project.lua`

`find_project_root_from_buffer()` walks the directory tree on every `M.setup()` call. Cache the result keyed by buffer path and invalidate on `BufWritePost` or directory change.

---

## 3. PENDINGS (Methodology gaps)

These are features described in `docs/metodologia.txt` not yet implemented.

### P1 — LLM integration (real API calls)
**File:** `lua/wyt/llm.lua`

`generate_text()` is a stub returning placeholder strings. Needs real HTTP calls to:
- OpenAI (`/v1/chat/completions`)
- Anthropic Claude (`/v1/messages`)

Options: use `vim.system()` with `curl`, or a Lua HTTP library. Also wire up:
- `llm.improve_idea(idea)` — improve idea text (TODO in `idea.lua:30`)
- `llm.suggest_group_name(ideas)` — name a group from idea list
- `llm.generate_paragraph(idea, context)` — expand idea into paragraph

---

### P2 — Export generation (`export.wyt.md`)
**File:** methodology §export.wyt.md

No command or function assembles the final export file from all `text.wyt.md` files following the section hierarchy. Needs a `:WYTExport` command that:
1. Walks the section tree in plan order
2. Concatenates `text.wyt.md` content (or `export.wyt.md` if newer)
3. Applies formatting per section type
4. Writes root `export.wyt.md`

---

### P3 — Text type differentiation (novel / short_story / essay / summary)
**File:** methodology §8

The plugin reads `type` from `config.wyt.yml` but never uses it to vary behavior. Each type should have:
- Different guided questions for idea generation
- Different paragraph generation logic (e.g. summary: multiple ideas → one paragraph)
- Separate config files per type in the plugin

---

### P4 — Section renaming should rename folder
**File:** methodology §section structure

"Cambiar el nombre del grupo en `plan.wyt.md` debe cambiar el nombre de la carpeta." Currently `rename_group` in `group.lua` only updates text in the plan file, not the corresponding `sections/slug/` directory.

---

### P5 — Navigate from idea to paragraph in `text.wyt.md`
**File:** methodology §7

When pressing `<S-Tab>` on an idea in the Ideas section (without a group tag), the plugin prints a debug message and opens `text.wyt.md` but does not position the cursor at the corresponding paragraph.

---

### P6 — Navigate from section plan to parent plan
**File:** methodology §7

`:WYTGoto parent` is implemented but `<S-Tab>` from within a sub-section plan does not offer navigation to the parent plan.

---

### P7 — Definition sections with search/reference support
**File:** methodology §type: definition

Sections of type `definition` (e.g. "Characters" in a novel) should be:
- Excluded from export
- Searchable/referenceable from content sections
- Needs a `:WYTSearch` or `:WYTRef` command to look up definitions while writing

---

### P8 — `WYTGenerate` should insert into buffer, not just print
**File:** `lua/wyt/commands.lua:67-75`

Currently `WYTGenerate` prints the result to the command line. It should insert generated text at cursor position in the current buffer (or open a float/split for review).

---

### P9 — `WYTSetLang` should persist language to `config.wyt.yml`
**File:** `lua/wyt/commands.lua:29-39`

The language change only lasts for the session. It should update the `lang:` key in the current project's `config.wyt.yml` so it persists across sessions.

---

### P10 — `:WYTNav` should show folder structure, not flat file list
**File:** `lua/wyt/commands.lua:77-100`

`vim.fn.glob()` returns all files but presents them as a flat list. The methodology calls for visualizing the section hierarchy. Consider:
- An indented tree display in the telescope picker
- Or integrate with nvim-tree / neo-tree

---

### P11 — Auto-commit on file write (not only on idea/group creation)
**File:** methodology §4

"se hace automáticamente a través de los comandos de la metodología y los comandos generales como guardar."
Currently git commits only happen when creating ideas, groups, or implementing groups. Should also commit on `:w` for plan/text files using `BufWritePost`.

---

### P12 — `:checkhealth wyt` module
**File:** `lua/wyt/health.lua` (missing)

No health check exists. Should verify:
- Neovim version >= 0.9
- `telescope.nvim` installed
- `git` executable in PATH
- Current buffer is inside a valid WYT project (optional)

---

### P13 — Tests
**File:** `tests/` (missing)

No tests for any module. Priority areas:
- `project.find_project_root_from_buffer()`
- `idea.sync_group_ideas_to_ideas()` (complex logic)
- `group.move_group()` (block swap)
- `plan.add_item_to_section()`

Use `plenary.nvim` busted or `nvim -l` with busted. See `docs/nvim-lua-best-practices.md §11`.

---

### P14 — Guided questions per text type and section level
**File:** methodology §8, §11

The methodology specifies that idea generation, grouping, and group naming should use "preguntas orientadoras" (guiding questions) that vary by:
- Literary text type (novel, essay, etc.)
- Section level (top-level vs subsection)

These question sets need to be defined (probably as Lua tables per type) and surfaced via the UI during idea/group creation.

---

### P15 — `text.wyt.md` paragraph expansion workflow
**File:** methodology §text.wyt.md

After implementing a group into `text.wyt.md`, each idea becomes a `*Create a paragraph about: [idea]*` placeholder. There is no command to:
- Expand a placeholder into a real paragraph (with or without LLM)
- Mark a placeholder as written
- Navigate between unwritten placeholders

---

## Status

### Completed
| Item | Description |
|------|-------------|
| O1 | Lazy requires in commands.lua |
| O2 | `vim.uv` instead of deprecated `vim.loop` |
| O3 | Debounced sync (300ms) |
| O4 | `vim.uv.fs_stat` instead of `vim.fn.filereadable` |
| O5 | `vim.tbl_deep_extend` in config.lua |
| O6 | `vim.notify` instead of `print` throughout |
| O7 | Removed forced buffer write in `group.new_group` |
| O8 | Extracted `swap_line_blocks` helper in `group.lua` |
| O10 | Per-buffer project root cache |
| F1 | Undefined `config_path`/`plan_path` in `set_section_data` |
| F2 | Stale project root cache when switching projects |
| F3 | Undeclared global `col` in plan.lua |
| F4 | No augroup → duplicate autocmds on re-setup |
| F5 | Path injection via unescaped `vim.cmd("e " .. path)` |
| F6 | Double slash in `current_section_dir .. "/text.wyt.md"` |
| F7 | `assert(uv.fs_open())` crash on unwritable paths |
| F8 | Global keymaps now buffer-local (only on plan.wyt.md buffers) |
| F9 | Language from config now applied to localization module |
| F10 | `add_item_to_section` API — accepts raw header text, not mixed key/string |
| F11 | `set_root_data`/`set_section_data` were globals, now `local` |
| F12 | Module-level telescope require in `idea.lua` moved inside function |
| F13 | Covered by F5 (path escaping + arrow guard already correct) |
| P4 | Section folder renamed when group is renamed |
| P5 | Cursor positioned in `text.wyt.md` after navigation |
| P6 | `<S-Tab>` on `# ` title navigates to parent plan |
| P8 | `:WYTGenerate` inserts text at cursor instead of just notifying |
| P9 | `:WYTSetLang` persists language to `config.wyt.yml` |
| P11 | Auto-commit on `:w` for plan.wyt.md and text.wyt.md |
| P12 | `:checkhealth wyt` module added |
| P13 | Test infrastructure + first spec file (`tests/plan_spec.lua`) |
| P1 | Real async LLM API calls via `vim.system(curl)` — OpenAI + Claude |
| P2 | `:WYTExport` — recursive section-tree export to `export.wyt.md` |
| P3 | `types.lua` — per-type questions/behavior (novel, essay, summary, short_story) |
| P7 | `:WYTSearch` — definition sections full-text search |
| P10 | `:WYTNav` — hierarchical tree display with indented entries |
| P14 | Guided questions for idea creation (idea.lua) and group naming (group.lua) |
| P15 | `:WYTExpand` / buffer keymaps — placeholder expansion with manual or LLM |
| O9 | `plugin/` directory — kept explicit `setup()`, documented in README |
