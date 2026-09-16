-- P10: hierarchical project navigation tree
local M = {}

local uv_ref = nil
local function uv() uv_ref = uv_ref or (vim.uv or vim.loop); return uv_ref end

-- Build a flat list of { label, path } entries representing the project tree.
-- `indent` grows with recursion depth.
local function build_tree(project_mod, dir, indent, entries)
    indent = indent or ""
    entries = entries or {}
    local sep = indent == "" and "" or "  "

    local files = {
        { name = "plan.wyt.md",   path = dir .. "plan.wyt.md" },
        { name = "text.wyt.md",   path = dir .. "text.wyt.md" },
        { name = "export.wyt.md", path = dir .. "export.wyt.md" },
        { name = "config.wyt.yml",path = dir .. "config.wyt.yml" },
    }
    for _, f in ipairs(files) do
        if uv().fs_stat(f.path) then
            table.insert(entries, { label = indent .. f.name, path = f.path })
        end
    end

    -- Walk group subdirectories in plan order
    local plan_path = dir .. "plan.wyt.md"
    if uv().fs_stat(plan_path) then
        local plan_content = project_mod.read_file(plan_path) or ""
        local groups = project_mod.get_groups(plan_content)
        for _, group_name in ipairs(groups) do
            local group_dir = project_mod.group_dir(dir, group_name)
            if group_dir then
                table.insert(entries, { label = indent .. group_dir:sub(#dir + 1), path = nil })
                build_tree(project_mod, group_dir, indent .. "  ", entries)
            end
        end
    end
    return entries
end

function M.navigate()
    local project = require("wyt.project")
    local loc = require("wyt.localization")
    if not project.setup() then return end

    local entries = build_tree(project, project.project_root)
    if #entries == 0 then
        vim.notify("[WYT] No files found in project.", vim.log.levels.WARN)
        return
    end

    local labels = {}
    for _, e in ipairs(entries) do
        table.insert(labels, e.label)
    end

    vim.ui.select(labels, { prompt = loc.t("nav_tree_select") }, function(choice)
        if not choice then return end
        for _, e in ipairs(entries) do
            if e.label == choice and e.path then
                require("wyt.ui").edit_file(e.path)
                return
            end
        end
    end)
end

return M
