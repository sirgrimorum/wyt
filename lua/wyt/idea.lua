local uv = vim.loop
local loc = require("wyt.localization")
local llm = require("wyt.llm")
local project = require("wyt.project")

local M = {}


local function section_name(key)
    local names = {
        Ideas = {en = "Ideas", es = "Ideas"},
        Groups = {en = "Groups", es = "Grupos"},
        ["Grupo: "] = {en = "Group: ", es = "Grupo: "}
    }
    return names[key] and (names[key][project.lang] or names[key]["en"]) or key
end

local function add_item_to_section(content, section, item)
    local section_header = "## " .. section_name(section)
    local section_start = content:find(section_header)
    if section_start then
        local next_section = content:find("\n## ", section_start + #section_header)
        if next_section then
            local before = content:sub(1, next_section - 1)
            local after = content:sub(next_section)
            before = before .. "\n- " .. item
            return before .. after
        else
            return content .. "\n- " .. item
        end
    else
        return content .. "\n\n" .. section_header .. "\n- " .. item
    end
end

local function get_groups(plan_path)
    local content = project.read_file(plan_path)
    if not content then return {} end
    local groups = {}
    local group_header = "## " .. section_name("Grupo: ")
    for group in content:gmatch(group_header .. "([^\n]+)") do
        table.insert(groups, group)
    end
    return groups
end

local function ensure_section_exists(content, section)
    local section_header = "## " .. section_name(section)
    if not content:find(section_header) then
        return content .. "\n" .. section_header .. "\n"
    end
    return content
end

function M.new_idea()
    local plan_content = project.read_file(project.plan_path) or ""
    -- Solo asegura la existencia de la sección, sin agregar ítem vacío
    plan_content = ensure_section_exists(plan_content, "Ideas")
    -- Detecta si existe la sección Grupos
    local groups = get_groups(project.plan_path)
    vim.ui.input({prompt = loc.t("idea_name")}, function(idea_name)
        if not idea_name or idea_name == "" then return end
        vim.ui.select({loc.t("yes"), loc.t("no")}, {prompt = loc.t("use_llm")}, function(use_llm)
            local final_idea = idea_name
            if use_llm == loc.t("yes") then
                -- ToDo: final_idea = llm.improve_idea(idea_name)
            end
            local group_selected = nil
            local function add_idea()
                plan_content = add_item_to_section(plan_content, "Ideas", final_idea)
                if group_selected then
                    plan_content = add_item_to_section(plan_content, "Grupo: " .. group_selected, final_idea)
                end
                project.write_file(project.plan_path, plan_content)
                project.commit_changes("Add idea: " .. idea_name)
                print(loc.t("idea_added") .. final_idea)
                vim.cmd("edit " .. project.plan_path)

                -- Buscar la línea de la idea recién agregada y mover el cursor
                local idea_line = nil
                local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
                for i, line in ipairs(lines) do
                    if line:find(final_idea, 1, true) then
                        idea_line = i
                        break
                    end
                end
                if idea_line then
                    vim.api.nvim_win_set_cursor(0, {idea_line, 0})
                end
                vim.cmd("normal! zz")
            end
            if #groups > 0 then
                vim.ui.select(groups, {prompt = loc.t("add_to_group")}, function(selected)
                    group_selected = selected
                    add_idea()
                end)
            else
                add_idea()
            end
        end)
    end)
end

return M