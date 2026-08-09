-- P2: assemble export.wyt.md from section tree
local M = {}

local function sections_enabled(config_path, project_mod)
    local cfg = project_mod.read_file(config_path) or ""
    return cfg:match("sections:%s*true") ~= nil
end

-- Recursively collect text from a section directory.
-- Returns a string with all content, or nil if nothing found.
local function collect_text(project_mod, section_dir, depth)
    depth = depth or 0
    local uv = vim.uv or vim.loop
    local config_path = section_dir .. "config.wyt.yml"
    local text_path   = section_dir .. "text.wyt.md"
    local plan_path   = section_dir .. "plan.wyt.md"

    -- A definition section is reference material: searchable while writing,
    -- never part of the exported text. The root is the project itself, so it is
    -- the one config this never applies to.
    if depth > 0 and project_mod.is_definition_section(section_dir) then return "" end

    if sections_enabled(config_path, project_mod) then
        local plan_content = project_mod.read_file(plan_path) or ""
        local groups = project_mod.get_groups(plan_content)
        local parts = {}
        for _, group_name in ipairs(groups) do
            local slug = project_mod.slugify(group_name)
            local group_dir = section_dir .. slug .. "/"
            if uv.fs_stat(group_dir .. "plan.wyt.md") then
                local sub_text = collect_text(project_mod, group_dir, depth + 1)
                if sub_text and sub_text ~= "" then
                    local heading = string.rep("#", depth + 2) .. " " .. group_name
                    table.insert(parts, heading .. "\n\n" .. sub_text)
                end
            end
        end
        return table.concat(parts, "\n\n")
    else
        if not uv.fs_stat(text_path) then return "" end
        local content = project_mod.read_file(text_path) or ""
        -- Strip unexpanded placeholders
        local loc = require("wyt.localization")
        local placeholder_en = "^%*" .. require("wyt.localization").translations.en.create_paragraph:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
        local placeholder_es = "^%*" .. require("wyt.localization").translations.es.create_paragraph:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
        local lines = vim.split(content, "\n", { plain = true })
        local result = {}
        for _, line in ipairs(lines) do
            if not line:match(placeholder_en) and not line:match(placeholder_es) then
                table.insert(result, line)
            end
        end
        -- Trim trailing blank lines
        while #result > 0 and result[#result] == "" do
            table.remove(result)
        end
        return table.concat(result, "\n")
    end
end

function M.export()
    local project = require("wyt.project")
    local loc = require("wyt.localization")
    if not project.setup() then return end

    vim.notify(loc.t("export_generating"), vim.log.levels.INFO)

    local text = collect_text(project, project.project_root)
    local plan_content = project.read_file(project.plan_path) or ""
    local title = plan_content:match("^# ([^\n]+)") or "Export"

    local export_content = "# " .. title .. "\n\n" .. (text or "")
    local export_path = project.project_root .. "export.wyt.md"
    project.write_file(export_path, export_content)
    project.commit_changes("Export: " .. title)

    vim.notify(loc.t("export_generated") .. export_path, vim.log.levels.INFO)
    vim.cmd("edit " .. vim.fn.fnameescape(export_path))
end

return M
