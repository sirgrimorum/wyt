-- P15: paragraph placeholder expansion workflow for text.wyt.md
local api = vim.api
local ui = require("wyt.ui")
local types = require("wyt.types")
local M = {}

local function placeholder_pattern(project_mod)
    -- create_paragraph ends with ": ", pattern captures idea name inside [...]
    local tag = project_mod.t("create_paragraph"):gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
    return "^%*" .. tag .. "%[(.-)%]%*$"
end

local function find_forward(lines, from, pat)
    for i = from, #lines do
        local m = lines[i]:match(pat)
        if m then return i, m end
    end
end

local function find_backward(lines, from, pat)
    for i = from, 1, -1 do
        local m = lines[i]:match(pat)
        if m then return i, m end
    end
end

-- Replace line `line_nr` (1-based) in `buf` with paragraph text.
local function do_expand(buf, line_nr, idea_name, project_mod, loc)
    vim.ui.select(
        { loc.t("expand_manually"), loc.t("expand_with_llm") },
        { prompt = loc.t("expand_how") },
        function(choice)
            if not choice then return end
            if choice == loc.t("expand_with_llm") then
                vim.notify(loc.t("llm_generating"), vim.log.levels.INFO)
                local plan_content = project_mod.read_file(project_mod.section_plan_path) or ""
                -- The same frame every other generation gets, plus the plan this
                -- placeholder sits in. Expanding used to know only that title,
                -- so it never learned what kind of text it was writing for.
                local context = project_mod.description_context(plan_content)
                local plan_title = plan_content:match("^#%s+([^\n]+)")
                if plan_title then context = context .. ". " .. plan_title end
                local project_type = project_mod.get_project_type()
                local lang = project_mod.lang
                require("wyt.llm").expand_idea(idea_name, context, lang, function(result, err)
                    if err or not result or result == "" then
                        if err then vim.notify(loc.t("llm_error") .. err, vim.log.levels.WARN) end
                        return
                    end
                    local new_lines = vim.split(result, "\n", { plain = true })
                    api.nvim_buf_set_lines(buf, line_nr - 1, line_nr, false, new_lines)
                    vim.notify(loc.t("placeholder_expanded"), vim.log.levels.INFO)
                end, {
                    prose_kind = types.prose_kind(project_type, lang),
                    -- A summary's placeholder holds a whole group's ideas.
                    merge = types.multi_idea_paragraph(project_type),
                })
            else
                -- The placeholder holds a whole idea, so it rarely fits a prompt
                -- line; the panel shows it in full while the writer types.
                ui.ask_input({
                    title = loc.t("paragraph_text"),
                    question = idea_name .. ":",
                }, function(text)
                    if not text or text == "" then return end
                    local new_lines = vim.split(text, "\n", { plain = true })
                    api.nvim_buf_set_lines(buf, line_nr - 1, line_nr, false, new_lines)
                    vim.notify(loc.t("placeholder_expanded"), vim.log.levels.INFO)
                end)
            end
        end
    )
end

function M.expand_at_cursor()
    local project = require("wyt.project")
    local loc = require("wyt.localization")
    if not project.setup() then return end

    local buf = api.nvim_get_current_buf()
    local cursor = api.nvim_win_get_cursor(0)[1]
    local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
    local pat = placeholder_pattern(project)
    local idea_name = lines[cursor] and lines[cursor]:match(pat)

    if not idea_name then
        vim.notify(loc.t("no_placeholder_at_cursor"), vim.log.levels.WARN)
        return
    end
    do_expand(buf, cursor, idea_name, project, loc)
end

function M.expand_next()
    local project = require("wyt.project")
    local loc = require("wyt.localization")
    if not project.setup() then return end

    local buf = api.nvim_get_current_buf()
    local cursor = api.nvim_win_get_cursor(0)[1]
    local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
    local pat = placeholder_pattern(project)
    local line_nr, idea_name = find_forward(lines, cursor + 1, pat)

    if not line_nr then
        vim.notify(loc.t("no_placeholder_below"), vim.log.levels.WARN)
        return
    end
    api.nvim_win_set_cursor(0, { line_nr, 0 })
    do_expand(buf, line_nr, idea_name, project, loc)
end

function M.expand_prev()
    local project = require("wyt.project")
    local loc = require("wyt.localization")
    if not project.setup() then return end

    local buf = api.nvim_get_current_buf()
    local cursor = api.nvim_win_get_cursor(0)[1]
    local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
    local pat = placeholder_pattern(project)
    local line_nr, idea_name = find_backward(lines, cursor - 1, pat)

    if not line_nr then
        vim.notify(loc.t("no_placeholder_above"), vim.log.levels.WARN)
        return
    end
    api.nvim_win_set_cursor(0, { line_nr, 0 })
    do_expand(buf, line_nr, idea_name, project, loc)
end

return M
