-- P7: search within definition-type sections
local M = {}

local uv_ref = nil
local function uv() uv_ref = uv_ref or (vim.uv or vim.loop); return uv_ref end

-- Collect the searchable files of every definition section under `dir`.
-- Both files count. A reference section is usually never implemented into prose
-- at all: a Characters section keeps each character as a group in its
-- `plan.wyt.md` and their traits as the ideas under it, so indexing only
-- `text.wyt.md` found nothing of what the writer went looking for.
local function collect_definition_files(project_mod, dir, results)
    results = results or {}
    local plan_path   = dir .. "plan.wyt.md"

    if project_mod.is_definition_section(dir) then
        for _, name in ipairs({ "plan.wyt.md", "text.wyt.md" }) do
            if uv().fs_stat(dir .. name) then
                table.insert(results, dir .. name)
            end
        end
    end

    -- Recurse into group subdirectories
    if uv().fs_stat(plan_path) then
        local plan_content = project_mod.read_file(plan_path) or ""
        local groups = project_mod.get_groups(plan_content)
        for _, group_name in ipairs(groups) do
            local slug = project_mod.slugify(group_name)
            -- An empty slug points the section at its own parent, and the walk
            -- never ends. Such a group has no folder: skip it.
            local group_dir = slug ~= "" and (dir .. slug .. "/") or nil
            if group_dir and uv().fs_stat(group_dir .. "plan.wyt.md") then
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
        local marker = project.t("group_tag") .. ": "
        for _, file_path in ipairs(def_files) do
            local content = project.read_file(file_path) or ""
            -- Relative path for display
            local rel = file_path:sub(#project.project_root + 1)
            -- A trait on its own says nothing about whose it is, so each hit
            -- carries the heading it sits under: the character, the concept.
            local heading = nil
            for lnum, line in ipairs(vim.split(content, "\n", { plain = true })) do
                local title = line:match("^#+%s+(.+)$")
                if title then
                    if title:sub(1, #marker) == marker then title = title:sub(#marker + 1) end
                    heading = project.clean_group_name(title)
                end
                if line:lower():find(query_lower, 1, true) then
                    local under = (not title and heading) and (" (" .. heading .. ")") or ""
                    table.insert(matches, {
                        label = rel .. ":" .. lnum .. under .. ": " .. vim.trim(line),
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
                    ui.edit_file(m.path)
                    vim.api.nvim_win_set_cursor(0, { m.lnum, 0 })
                    vim.cmd("normal! zz")
                    return
                end
            end
        end)
    end)
end

return M
