-- P2: assemble export.wyt.md from section tree
local types = require("wyt.types")
local loc = require("wyt.localization")

local M = {}

local function sections_enabled(config_path, project_mod)
    local cfg = project_mod.read_file(config_path) or ""
    return project_mod.config_value(cfg, "sections") == "true"
end

-- Join blocks that carry no heading of their own. A type that marks scene
-- changes gets its separator between them; the rest simply run on.
local function join(parts, spec)
    local separator = "\n\n"
    if spec and spec.break_with then
        separator = "\n\n" .. spec.break_with .. "\n\n"
    end
    return table.concat(parts, separator)
end

-- `## Group: <name>` inside text.wyt.md is WYT's own marker, not part of the
-- finished document: it is how a group is found again when it is re-implemented.
-- What the reader should see in its place is the type's business, so it becomes
-- a heading, a scene break, or nothing at all.
local function split_group_blocks(lines, project_mod)
    local marker = "^##%s+" .. vim.pesc(project_mod.t("group_tag")) .. ":%s*(.+)$"
    local blocks, names = {}, {}
    local current, pending = {}, nil
    local function flush()
        while #current > 0 and current[1]:match("^%s*$") do table.remove(current, 1) end
        while #current > 0 and current[#current]:match("^%s*$") do table.remove(current) end
        -- A group whose paragraphs are all still placeholders contributes
        -- nothing, and its name goes with it.
        if #current > 0 then
            blocks[#blocks + 1] = table.concat(current, "\n")
            names[#blocks] = pending
        end
        current, pending = {}, nil
    end
    for _, line in ipairs(lines) do
        local name = line:match(marker)
        if name then
            flush()
            pending = project_mod.clean_group_name(name)
        else
            current[#current + 1] = line
        end
    end
    flush()
    return blocks, names
end

-- Recursively collect text from a section directory.
-- `level` counts the project root as 1, matching the type's outline map.
-- `project_type` is read once by the caller: it lives in the root config, and
-- reading that file again at every node of the tree bought nothing.
local function collect_text(project_mod, section_dir, level, project_type)
    local uv = vim.uv or vim.loop
    local config_path = section_dir .. "config.wyt.yml"
    local text_path   = section_dir .. "text.wyt.md"
    local plan_path   = section_dir .. "plan.wyt.md"

    -- A definition section is reference material: searchable while writing,
    -- never part of the exported text. The root is the project itself, so it is
    -- the one config this never applies to.
    if level > 1 and project_mod.is_definition_section(section_dir) then return "" end

    if sections_enabled(config_path, project_mod) then
        local plan_content = project_mod.read_file(plan_path) or ""
        local groups = project_mod.get_groups(plan_content)
        -- Sections of this parent all sit one level down, so they share a spec.
        local spec = types.outline(project_type, level + 1)
        local parts = {}
        for _, group_name in ipairs(groups) do
            local slug = project_mod.slugify(group_name)
            -- An empty slug points the section at its own parent, and the walk
            -- never ends. Such a group has no folder: skip it.
            local group_dir = slug ~= "" and (section_dir .. slug .. "/") or nil
            if group_dir and uv.fs_stat(group_dir .. "plan.wyt.md") then
                local sub_text = collect_text(project_mod, group_dir, level + 1, project_type)
                if sub_text and sub_text ~= "" then
                    if spec and spec.heading then
                        sub_text = string.rep("#", spec.heading) .. " " .. group_name
                            .. "\n\n" .. sub_text
                    end
                    table.insert(parts, sub_text)
                end
            end
        end
        return join(parts, spec)
    end

    if not uv.fs_stat(text_path) then return "" end
    local content = project_mod.read_file(text_path) or ""

    -- Strip unexpanded placeholders, in either language: the writer never got
    -- to them, and an instruction to themselves is not part of the text.
    local placeholder_en = "^%*" .. vim.pesc(loc.translations.en.create_paragraph)
    local placeholder_es = "^%*" .. vim.pesc(loc.translations.es.create_paragraph)
    -- Re-implementing a group parks the text of groups no longer in the plan in
    -- a fence tagged `old`: kept for the writer, not part of the document. The
    -- fences are written back to back, so "``````old" closes one and opens the next.
    local kept, in_old = {}, false
    for _, line in ipairs(vim.split(content, "\n", { plain = true })) do
        if in_old then
            if line:match("^```") then in_old = line:match("^```.*```old") ~= nil end
        elseif line:match("^```old") then
            in_old = true
        elseif not line:match(placeholder_en) and not line:match(placeholder_es) then
            kept[#kept + 1] = line
        end
    end

    local spec = types.group_outline(project_type)
    local blocks, names = split_group_blocks(kept, project_mod)
    if spec and spec.heading then
        for i, block in ipairs(blocks) do
            if names[i] then
                blocks[i] = string.rep("#", spec.heading) .. " " .. names[i] .. "\n\n" .. block
            end
        end
    end
    return join(blocks, spec)
end

function M.export()
    local project = require("wyt.project")
    if not project.setup() then return end
    -- The export reads from disk, so an edit still in the buffer would be left
    -- out, then saved and committed after the export that missed it.
    require("wyt.ui").save_current()

    vim.notify(loc.t("export_generating"), vim.log.levels.INFO)

    local text = collect_text(project, project.project_root, 1, project.get_project_type())
    local plan_content = project.read_file(project.plan_path) or ""
    local title = plan_content:match("^# ([^\n]+)") or "Export"

    local export_content = "# " .. title .. "\n\n" .. (text or "") .. "\n"
    local export_path = project.project_root .. "export.wyt.md"
    project.write_file(export_path, export_content)
    project.commit_changes("Export: " .. title)

    vim.notify(loc.t("export_generated") .. export_path, vim.log.levels.INFO)
    require("wyt.ui").edit_file(export_path)
end

return M
