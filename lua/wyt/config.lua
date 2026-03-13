local M = {}

M.options = {
    llm_provider = "openai", -- "openai" o "claude"
    api_key = "",
}

function M.setup(opts)
    M.options = vim.tbl_deep_extend("force", M.options, opts or {})
end

return M
