# Working on WYT

A Neovim plugin, Lua, for structured long-form writing. A project is plain text
in nested folders: `plan.wyt.md` (Description / Ideas / Groups),
`text.wyt.md` (prose, one placeholder per idea), `config.wyt.yml`, and
`export.wyt.md` assembled from the rest.

## Run the tests

```sh
nvim --headless -l tests/runner.lua              # everything, ~1s
nvim --headless -l tests/runner.lua types llm    # only those specs
```

Exits 1 on failure. Nothing to install. Run it before you hand work back.

**Add a `tests/<thing>_spec.lua` rather than a throwaway script.** Writing one
throws away the setup next time and does not run again. `tests/README.md` has
the fixtures and the assertion surface; `tests/helpers.lua` builds a project on
disk, scripts `vim.ui`, and captures the prompt a generation would have sent.

plenary.nvim is deliberately not a dependency: `PlenaryBustedDirectory` hangs
forever when it is missing, which is why the suite ships its own runner.

## Things that have cost real time

- **A section exists only if its parent's plan names it as a group**, slugified.
  Creating the folder is not enough: the export, `:WYTNav` and `:WYTSearch` all
  walk group names and will skip it. This is the single most common way a
  fixture or a manual repro goes quietly wrong.
- **Lua patterns are byte-oriented.** Never put a multibyte character in a
  `[...]` class: `¿` is `0xC2 0xBF` and `«` is `0xC2 0xAB`, so `[«]` eats the
  `0xC2` off every Spanish question. Match such tokens whole. Also `%w`
  excludes `_`, which once made `short_story` read as `short` and silently fall
  back to `essay`; use `[%w_]` for type and key names.
- **`vim.ui.input` returns `""` on an empty confirm and `nil` on `<Esc>`.** They
  mean different things everywhere in this codebase. Do not collapse them.
- **Windows paths arrive with either separator.** Match `[\\/]`, and normalise
  both sides before comparing two paths.
- **A file ending in a newline loads one line shorter than the array that wrote
  it.** A spec that addresses a row should set the buffer lines directly.
- **A project created inside another project resolves its root to the outer
  config.** Build each fixture in its own temp directory.

## Design decisions, settled. Do not relitigate

- **Depth is per section, not a config key.** A section's own `sections: true`
  is the lever: hand-edit it and that branch alone nests deeper, past its type's
  max, even when its siblings say `false`. `types.section_depth()` is only the
  default written at creation. A level past the type's outline map comes out
  untitled in the export, which is accepted.
- **The export never calls the LLM.** It assembles what was written.
- **A model reply that lands in a file is stripped** of headings, fences and
  list markers (`llm.to_prose`, `llm.to_single_line`). A `#` the model invents
  would become export structure, and a name carrying `##` would carry it into
  the folder slug.
- **The type reaches the model under its localized name**, never the id:
  `Novela larga`, not `long_novel`. Each type also asks for its own kind of
  paragraph (`types.prose_kind`).
- **A long prompt goes in a `ui.preview` panel** with a short title, never in
  the select or input prompt line, which renders as a single truncated line.
- **Every yes/no is a menu**, never a typed `y`.
- **A section's archetype** (`section_kind`) decides its guided questions, its
  `content_type`, and whether `:WYTSearch` sees it. Asked once at creation; a
  section inside a reference section inherits it without asking.

## Docs, and which is which

- `USER_GUIDE.md` is **Spanish** and holds the rules: every command, the text
  types with their depth and paragraph logic, the export's title map, the
  section archetypes.
- `docs/use_case_e2e.md` is **English** and is one worked example, read once,
  start to finish. It links to the guide rather than restating it.
- `README.md` is **Spanish**: install, API key handling, local development.
- `tests/README.md` is **English**: how to run and write a spec.

Keep a doc change in the same commit as the behaviour it describes. The
walkthrough has drifted from the code before in ways that read as plausible;
when in doubt, run something and paste the real output rather than trusting the
prose.

## Conventions

- No em dashes in prose, docs, comments or commit messages.
- Comments say **why**, not what. Match the density and voice already in the
  file: most explain a decision or a bug that is not visible from the code.
- Commit messages are one-liners: a conventional prefix and a subject under 72
  characters. No body, no bullet list, no `Co-Authored-By` trailer.
- `.claude/settings.local.json` is never staged.
