# Neovim Plugin Development — Lua Patterns & Best Practices

Compiled from official Neovim docs, nvim-neorocks/nvim-best-practices, and community consensus (2024-2025).

---

## 1. Directory Structure

```
my-plugin.nvim/
├── plugin/
│   └── myplugin.lua    ← sourced automatically at startup; KEEP TINY
├── lua/
│   └── myplugin/
│       ├── init.lua    ← public API + M.setup()
│       ├── config.lua  ← defaults, validation
│       ├── core.lua    ← main logic (loaded lazily)
│       └── health.lua  ← :checkhealth myplugin
├── ftplugin/
│   └── markdown.lua    ← loaded per filetype buffer
└── tests/
    ├── minimal_init.lua
    └── myplugin_spec.lua
```

**Rules:**
- `plugin/` — runs once at startup. Only register commands/mappings/autocmds. Never `require()` heavy modules here.
- `lua/` — everything here is lazy. Lua caches `require()` results in `package.loaded`, so only the first call pays the cost.
- `ftplugin/` — runs on every matching buffer open. Use for buffer-local setup.

---

## 2. Lazy Loading with `require()`

```lua
-- plugin/myplugin.lua  (startup — stays minimal)
vim.api.nvim_create_user_command("MyPlugin", function(args)
  require("myplugin").run(args)   -- require() INSIDE callback, not at top
end, { nargs = "*", desc = "Run MyPlugin" })

vim.keymap.set("n", "<leader>mp", function()
  require("myplugin").action()    -- lazy inside closure
end, { desc = "MyPlugin action" })
```

**Anti-pattern — eager requires at module top level:**
```lua
-- BAD in init.lua or commands.lua
local core = require("myplugin.core")       -- loads immediately on setup()
local telescope = require("telescope")       -- crashes if not installed
```

**Good — require inside function bodies:**
```lua
-- GOOD
function M.open()
  local core = require("myplugin.core")     -- loaded on first call
  core.open()
end
```

---

## 3. The `setup()` Pattern

Separate configuration from initialization:

```lua
-- lua/myplugin/config.lua
local M = {}

M.defaults = {
  llm_provider = "openai",
  api_key = "",
  lang = "en",
}

function M.setup(opts)
  -- Use deep_extend to properly merge nested tables
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

return M
```

```lua
-- lua/myplugin/init.lua
local M = {}

function M.setup(opts)
  require("myplugin.config").setup(opts)
  -- defer actual init — register commands/autocmds/maps here
  -- but don't require heavy modules yet
  require("myplugin.commands").setup()
  require("myplugin.autocmd").setup()
  require("myplugin.mappings").setup()
end

return M
```

**`vim.tbl_deep_extend` vs `vim.tbl_extend`:**
- `vim.tbl_extend("force", ...)` — shallow merge (nested tables replaced wholesale)
- `vim.tbl_deep_extend("force", ...)` — recursive merge (nested tables merged key by key)

---

## 4. Autocommands — Always Use Augroups

Without an augroup, calling `setup()` twice duplicates every autocmd:

```lua
-- BAD — no augroup, duplicates on re-setup
vim.api.nvim_create_autocmd("BufWritePost", {
  pattern = "*.md",
  callback = function() end,
})

-- GOOD — augroup with clear=true prevents duplication
local group = vim.api.nvim_create_augroup("MyPlugin", { clear = true })

vim.api.nvim_create_autocmd("BufWritePost", {
  group = group,
  pattern = "*.md",
  callback = function(ev)
    require("myplugin").on_save(ev.buf)
  end,
  desc = "MyPlugin: sync on save",
})
```

---

## 5. Keymaps — Prefer Buffer-Local for File-Specific Plugins

Global keymaps from plugins pollute key bindings in every buffer:

```lua
-- BAD — <S-Tab> stolen in ALL buffers globally
vim.keymap.set("n", "<S-Tab>", some_fn, { desc = "Navigate" })

-- GOOD — only active in buffers with the plugin's filetype
vim.api.nvim_create_autocmd("BufEnter", {
  group = group,
  pattern = "plan.wyt.md",
  callback = function(ev)
    vim.keymap.set("n", "<S-Tab>", some_fn, {
      buffer = ev.buf,
      desc = "WYT: navigate",
    })
  end,
})
```

Always pass `desc` for discoverability via `:map` and which-key.

---

## 6. Error Handling

```lua
-- pcall for recoverable operations
local ok, err = pcall(function()
  vim.api.nvim_win_close(win_id, false)
end)
if not ok then
  vim.notify("Could not close window: " .. err, vim.log.levels.WARN)
end

-- Return nil, err for file I/O instead of assert()
function M.read_file(path)
  local fd = vim.uv.fs_open(path, "r", 438)
  if not fd then
    return nil, "cannot open: " .. path
  end
  local stat = vim.uv.fs_fstat(fd)
  local data = vim.uv.fs_read(fd, stat.size, 0)
  vim.uv.fs_close(fd)
  return data
end

-- assert() only for programmer errors (wrong types passed to your API)
function M.setup(opts)
  assert(type(opts) == "table" or opts == nil, "opts must be a table")
end
```

**Use `vim.notify` instead of `print`:**
```lua
-- BAD
print("[MyPlugin] Something happened")

-- GOOD
vim.notify("Something happened", vim.log.levels.INFO, { title = "MyPlugin" })
vim.notify("Warning message", vim.log.levels.WARN, { title = "MyPlugin" })
vim.notify("Fatal error", vim.log.levels.ERROR, { title = "MyPlugin" })
```

---

## 7. Safe `vim.cmd` — Always Escape Paths

Unescaped paths cause command injection if filenames contain spaces or special chars:

```lua
-- BAD — path injection
vim.cmd("e " .. path)
vim.cmd("tabnew " .. path)

-- GOOD — use fnameescape()
vim.cmd("e " .. vim.fn.fnameescape(path))

-- BETTER — use API directly (no string concatenation)
vim.cmd.edit(path)                        -- Neovim 0.8+
vim.cmd.tabnew(path)
vim.api.nvim_command("edit " .. vim.fn.fnameescape(path))
```

---

## 8. `vim.api` vs `vim.fn`

- Prefer `vim.api.*` for new code — native Lua types, faster.
- Use `vim.fn.*` only when no `vim.api` equivalent exists.

```lua
-- prefer vim.api
local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, new_lines)

-- vim.fn is fine for utilities without api equivalent
local escaped = vim.fn.fnameescape(path)
local expanded = vim.fn.expand("%:p")
local readable = vim.fn.filereadable(path) == 1
-- or with vim.uv:
local stat = vim.uv.fs_stat(path)  -- returns nil if not found
```

---

## 9. Async and `vim.uv` (libuv)

`vim.loop` is deprecated — use `vim.uv`:

```lua
-- Sync file read (blocks main loop — OK for small files)
local fd = vim.uv.fs_open(path, "r", 438)
if not fd then return nil end
local stat = vim.uv.fs_fstat(fd)
local data = vim.uv.fs_read(fd, stat.size, 0)
vim.uv.fs_close(fd)
return data

-- CRITICAL: never call vim.api from uv callbacks directly
-- Wrap with vim.schedule()
vim.uv.fs_read(fd, size, 0, function(err, data)
  vim.schedule(function()
    -- safe to call vim.api here
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, { data })
  end)
end)
```

---

## 10. Checking Optional Dependencies

```lua
-- In setup() or lazily before use
local has_telescope, telescope = pcall(require, "telescope")
if not has_telescope then
  vim.notify(
    "MyPlugin: telescope.nvim is required for multi-select",
    vim.log.levels.ERROR,
    { title = "MyPlugin" }
  )
  return
end
```

---

## 11. Health Checks

Every plugin should implement `:checkhealth`:

```lua
-- lua/myplugin/health.lua
local M = {}

function M.check()
  vim.health.start("myplugin")

  if vim.fn.has("nvim-0.9") == 1 then
    vim.health.ok("Neovim >= 0.9")
  else
    vim.health.error("Neovim >= 0.9 required")
  end

  local ok = pcall(require, "telescope")
  if ok then
    vim.health.ok("telescope.nvim found")
  else
    vim.health.error("telescope.nvim required", {
      "Install via your plugin manager"
    })
  end

  if vim.fn.executable("git") == 1 then
    vim.health.ok("git found in PATH")
  else
    vim.health.warn("git not found — version control disabled")
  end
end

return M
```

Users run: `:checkhealth myplugin`

---

## 12. Command Completion

```lua
vim.api.nvim_create_user_command("MyCmd", function(args)
  -- args.fargs[1] is the subcommand
end, {
  nargs = "?",
  complete = function(arglead, cmdline, cursorpos)
    -- arglead: what user has typed so far
    -- filter based on arglead for good UX
    local all = { "open", "close", "toggle" }
    return vim.tbl_filter(function(v)
      return v:find(arglead, 1, true) == 1
    end, all)
  end,
  desc = "My plugin command",
})
```

---

## 13. Avoiding Global State Leaks

```lua
-- BAD — local helper functions without `local` keyword become globals
function set_root_data()   -- global!
  -- ...
end

-- GOOD
local function set_root_data()
  -- ...
end
```

---

## 14. Debouncing Expensive Callbacks

For autocmds on TextChanged (fires very frequently):

```lua
local timer = nil

local function debounce(fn, ms)
  return function(...)
    local args = { ... }
    if timer then
      timer:stop()
      timer:close()
    end
    timer = vim.uv.new_timer()
    timer:start(ms, 0, vim.schedule_wrap(function()
      fn(unpack(args))
    end))
  end
end

vim.api.nvim_create_autocmd({"TextChanged", "InsertLeave"}, {
  group = group,
  pattern = "*plan.wyt.md",
  callback = debounce(function() require("myplugin.idea").sync() end, 300),
})
```

---

## 15. Key References

- [neovim.io/doc/user/lua-guide.html](https://neovim.io/doc/user/lua-guide.html) — official Lua in Neovim guide
- [neovim.io/doc/user/lua-plugin.html](https://neovim.io/doc/user/lua-plugin.html) — official plugin authoring docs
- [github.com/nvim-neorocks/nvim-best-practices](https://github.com/nvim-neorocks/nvim-best-practices) — community DOs and DON'Ts
- [zignar.net: Structuring Neovim Lua plugins](https://zignar.net/2022/11/06/structuring-neovim-lua-plugins/)
- [hiphish.github.io: Testing Neovim plugins with Busted](https://hiphish.github.io/blog/2024/01/29/testing-neovim-plugins-with-busted/)
