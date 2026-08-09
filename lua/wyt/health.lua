local M = {}

function M.check()
    vim.health.start("wyt")

    -- Neovim version
    if vim.fn.has("nvim-0.9") == 1 then
        vim.health.ok("Neovim >= 0.9")
    else
        vim.health.error("Neovim >= 0.9 is required")
    end

    -- telescope.nvim (required for multi-select)
    local ok = pcall(require, "telescope")
    if ok then
        vim.health.ok("telescope.nvim is installed")
    else
        vim.health.error(
            "telescope.nvim is required for multi-select features",
            { "Install: https://github.com/nvim-telescope/telescope.nvim" }
        )
    end

    -- git (required for version control integration)
    if vim.fn.executable("git") == 1 then
        vim.health.ok("git found in PATH")
    else
        vim.health.warn("git not found in PATH — version control features will not work")
    end

    -- setup() was called
    local config_ok, config = pcall(require, "wyt.config")
    if config_ok and config.options then
        vim.health.ok("setup() has been called")
        local provider = config.options.llm_provider
        if provider == "openai" or provider == "claude" then
            vim.health.ok("LLM provider: " .. provider)
        else
            vim.health.warn("Unknown LLM provider: " .. tostring(provider))
        end
        -- Report the source only. The key itself is never printed, and
        -- resolvers are not invoked here: :checkhealth should not unlock a
        -- keychain or pop an input prompt as a side effect.
        local source = config.api_key_source()
        if source == "resolver" then
            vim.health.ok("API key: lazy resolver (fetched on first request, not stored on disk)")
        elseif source == "literal" then
            vim.health.warn(
                "API key: literal string in your config",
                {
                    "A literal key sits in plaintext in a file that is often git-tracked.",
                    "Prefer a resolver: api_key = require('wyt.secret').os_store()",
                }
            )
        else
            vim.health.warn("API key is not configured — :WYTGenerate will not work until set with :WYTConfig")
        end
    else
        vim.health.error(
            "setup() has not been called",
            { "Add require('wyt').setup({...}) to your Neovim config" }
        )
    end

    -- WYT project in current buffer
    local project_ok, project = pcall(require, "wyt.project")
    if project_ok and project.setup() then
        vim.health.ok("WYT project found at: " .. project.project_root)
        vim.health.info("Project language: " .. project.lang)
    else
        vim.health.info("No WYT project detected in current buffer (normal when outside a project)")
    end
end

return M
