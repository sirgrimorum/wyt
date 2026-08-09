-- P7: search within definition-type sections
local M = {}

local uv_ref = nil
local function uv() uv_ref = uv_ref or (vim.uv or vim.loop); return uv_ref end

local function is_definition(config_path, project_mod)
    local cfg = project_mod.read_file(config_path) or ""
    return cfg:match("content_type:%s*definition") ~= nil
end

-- Collect all definition text.wyt.md files under `dir` recursively.
local function collect_definition_files(project_mod, dir, results)
    results = results or {}
    local config_path = dir .. "config.wyt.yml"
    local text_path   = dir .. "text.wyt.md"
    local plan_path   = dir .. "plan.wyt.md"

    if uv().fs_stat(text_path) and uv().fs_stat(config_path) and is_definition(config_path, project_mod) then
        table.insert(results, text_path)
    end

    -- Recurse into group subdirectories
    if uv().fs_stat(plan_path) then
        local plan_content = project_mod.read_file(plan_path) or ""
        local groups = project_mod.get_groups(plan_content)
        for _, group_name in ipairs(groups) do
            local slug = project_mod.slugify(group_name)
            local group_dir = dir .. slug .. "/"
            if uv().fs_stat(group_dir .. "plan.wyt.md") then
                collect_definition_files(project_mod, group_dir, results)
            end
        end
    end
    return results
end

function M.search()
    local project = require("wyt.project")
    local loc = require("wyt.localization")
    local ui = require("wyt.ui")
    if not project.setup() then return end

    local def_files = collect_definition_files(project, project.project_root)
    if #def_files == 0 then
        vim.notify(loc.t("no_definitions_found"), vim.log.levels.WARN)
        return
    end

    vim.ui.input({ prompt = loc.prompt("search_query_prompt") }, function(query)
        if not query or query == "" then return end
        local query_lower = query:lower()

        local matches = {}
        for _, file_path in ipairs(def_files) do
            local content = project.read_file(file_path) or ""
            local lines = vim.split(content, "\n", { plain = true })
            for lnum, line in ipairs(lines) do
                if line:lower():find(query_lower, 1, true) then
                    -- Relative path for display
                    local rel = file_path:sub(#project.project_root + 1)
                    table.insert(matches, {
                        label = rel .. ":" .. lnum .. ": " .. vim.trim(line),
                        path  = file_path,
                        lnum  = lnum,
                    })
                end
            end
        end

        if #matches == 0 then
            vim.notify(loc.t("search_no_results") .. query, vim.log.levels.INFO)
            return
        end

        local labels = {}
        for _, m in ipairs(matches) do table.insert(labels, m.label) end

        -- The query is whatever the writer typed, so it can outgrow a prompt.
        ui.ask_select({ title = loc.t("search_desc"), question = query }, labels, function(choice)
            if not choice then return end
            for _, m in ipairs(matches) do
                if m.label == choice then
                    vim.cmd("edit " .. vim.fn.fnameescape(m.path))
                    vim.api.nvim_win_set_cursor(0, { m.lnum, 0 })
                    vim.cmd("normal! zz")
                    return
                end
            end
        end)
    end)
end

return M
