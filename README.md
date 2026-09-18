# WYT.nvim

A Neovim plugin for managing long-form writing projects with the WYT method.

## Requirements

- Neovim >= 0.10
- [`telescope.nvim`](https://github.com/nvim-telescope/telescope.nvim)
- `git` and `curl` on the PATH

WYT does not initialise itself. Without a call to `require("wyt").setup(...)` no command or
mapping is registered.

## Installation

### lazy.nvim

```lua
{
  "your_user/wyt.nvim",
  dependencies = { "nvim-telescope/telescope.nvim" },
  config = function()
    require("wyt").setup({
      llm_provider = "claude",  -- "openai" | "claude"
      api_key = require("wyt.secret").os_store(),
    })
  end,
}
```

### packer.nvim

```lua
use({
  "your_user/wyt.nvim",
  requires = { "nvim-telescope/telescope.nvim" },
  config = function()
    require("wyt").setup({
      llm_provider = "claude",  -- "openai" | "claude"
      api_key = require("wyt.secret").os_store(),
    })
  end,
})
```

### Without a plugin manager

```lua
vim.opt.runtimepath:append("/path/to/wyt.nvim")
require("wyt").setup({
  llm_provider = "claude",  -- "openai" | "claude"
  api_key = require("wyt.secret").os_store(),
})
```

If you also use lazy.nvim, this block goes **after** `require('lazy').setup(...)`.
See [Local development](#local-development).

## Configuration

```lua
require("wyt").setup({
  llm_provider = "openai",  -- "openai" | "claude"
  api_key = "",             -- string | function(): string
})
```

## API key

`api_key` takes a string or a function. If you pass a function, WYT calls it on the first LLM
request, not at startup, and keeps the result in memory for the rest of the session. The key is
never written into your configuration.

The `wyt.secret` module ships ready-made resolvers:

| Resolver | Where it reads the key from |
| --- | --- |
| `secret.os_store()` | The operating system's native store. Recommended. |
| `secret.dpapi()` | Windows, a DPAPI-encrypted file |
| `secret.keychain("wyt")` | macOS Keychain |
| `secret.libsecret("wyt")` | Linux, libsecret or gnome-keyring |
| `secret.prompt()` | Asks once per session. Never touches the disk. |
| `secret.file("~/.wyt-key")` | Plain file. Use permissions 600. |
| `secret.command({ "pass", "show", "anthropic" })` | The output of any command |
| `secret.env("ANTHROPIC_API_KEY")` | Environment variable. See [below](#why-not-an-environment-variable). |

### Storing the key

**Windows (DPAPI).** The encryption is tied to your user and this machine, so the file is useless
on another computer. `Read-Host` keeps the key out of the PowerShell history.

```powershell
$dir = "$env:LOCALAPPDATA\nvim-data\wyt"
New-Item -ItemType Directory -Force -Path $dir | Out-Null
Read-Host -AsSecureString "API key" | ConvertFrom-SecureString |
  Set-Content -LiteralPath "$dir\api_key.dpapi"
```

**macOS (Keychain).** Without `-w <value>`, `security` asks for the key interactively.

```bash
security add-generic-password -s wyt -a "$USER" -w
```

**Linux (libsecret).** `secret-tool store` reads the key from stdin.

```bash
secret-tool store --label="WYT" service wyt account default
```

### Switching provider

```
:WYTConfig claude
```

With no second argument, WYT asks for the key with `inputsecret`, with no echo and without going
through `:history`. If you type it on the command line, WYT warns you and deletes the history
entry, but by then it has already been on screen. Use the prompt.

### Why not an environment variable

A user environment variable is inherited by every process you start: LSP servers, formatters,
build scripts, terminal jobs. It also shows up in crash dumps and in the output of `env`. A
resolver is consulted only when WYT needs it.

This does not protect against malware already running as your user, because that code can read
your keychain too. What it prevents is the key being ambiently available to processes that have
nothing to do with WYT.

## Local development

To use a local checkout instead of the installed version, add the path to the `runtimepath` and
call `setup()`:

```lua
require('lazy').setup({
  -- ... your plugins ...
})

-- Goes AFTER lazy.setup(): lazy rebuilds 'runtimepath' and drops any path
-- added before that call.
local wyt_path = os.getenv('WYT_PATH')
if wyt_path then
  vim.opt.runtimepath:append(wyt_path)
  require('wyt').setup({
    llm_provider = 'claude',  -- "openai" | "claude"
    api_key = require('wyt.secret').os_store(),
  })
end
```

WYT is loaded entirely through `require`, and `require` looks inside `lua/` of every
`runtimepath` entry: that `append` line is what lets `require('wyt')` find the checkout. If the
block runs before `lazy.setup()`, lazy rebuilds the `runtimepath` and the path is lost: what is
already loaded keeps answering in that session, but the next `require` of a submodule, and any
restart, fails. To check:

```vim
:lua print(vim.o.runtimepath:find('WYT') ~= nil)
```

Do not write the API key literally in `init.lua`. That file is usually versioned in git, and a
plain-text key there ends up published. Use a resolver from [`wyt.secret`](#api-key).

### Quick test without editing init.lua

```vim
:lua vim.opt.runtimepath:append("C:/path/to/WYT"); require("wyt").setup()
```

Use forward slashes on Windows: backslashes are escapes inside a Lua string. The change lasts
only for the current session.

### Setting WYT_PATH

Only the checkout path goes in an environment variable. The API key does not.

Windows PowerShell:

```powershell
[System.Environment]::SetEnvironmentVariable("WYT_PATH", "C:\your\path", "User")
```

macOS and Linux, in `~/.bashrc` or `~/.zshrc`:

```bash
export WYT_PATH="/your/path"
```

Either way, restart the terminal or reload the profile.

## Checking the installation

```vim
:checkhealth wyt
```

Reports the Neovim version, telescope, git, the LLM provider and where the API key comes from. It
never prints the key.

## Tests

```sh
nvim --headless -l tests/runner.lua              # everything
nvim --headless -l tests/runner.lua types llm    # only those specs
```

Nothing to install and no LLM calls: the tests replace `generate_text` with a double, so they run
without an API key. Exits with code 1 if anything fails. See [tests/README.md](./tests/README.md)
to write one.

## What files and folders does it create?

- `plan.wyt.md`: the plan of the project or section.
- `config.wyt.yml`: the configuration of the section or project.
- `text.wyt.md`: the prose, written or generated.
- `export.wyt.md`: the final export of the text.
- A folder structure for sections and sub-sections, following the method.

## Which files should I edit?

Do not edit the plugin's internal files. Edit your project's files (`plan.wyt.md`,
`text.wyt.md`, and so on) with Neovim and the plugin's commands.

## Basic usage

1. Run `:WYTNew p` to create a new writing project.
2. Navigate and manage your project with the commands and mappings.
3. Edit and organise your ideas, groups and texts in the generated files.

## Documentation

- [Quick guide](./docs/quick_guide.md): one page for daily use, the WYT keys and commands plus
  the Neovim you need to write with it. There is also a
  [printable version](https://sirgrimorum.github.io/wyt/quick_guide.html) to share or pin up.
- [User guide](./USER_GUIDE.md): every command and mapping, the automatic behaviour, the text
  types with their depth and paragraph logic, the export's outline map and the section
  archetypes (characters, chronology, turning points, key concepts, sources).
- [Full use case](./docs/use_case_e2e.md): the method from start to finish, from an empty
  directory to the final export.
- [Tests](./tests/README.md): how to run the suite and how to write a spec.
- [AGENTS.md](./AGENTS.md): for contributing, with or without a coding assistant. The decisions
  already made and the traps that have cost time.

---

Questions or suggestions? Open an issue or contribute!
