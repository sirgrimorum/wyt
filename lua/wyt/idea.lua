local uv = vim.loop
local api = vim.api
local loc = require("wyt.localization")
local llm = require("wyt.llm")
local project = require("wyt.project")
local group = require("wyt.group")

local M = {}

local function ensure_section_exists(content, section)
    local section_header = "## " .. project.t(section)
    if not content:find(section_header) then
        return content .. "\n" .. section_header .. "\n"
    end
    return content
end

local multi_select = require("wyt.group").multi_select

function M.new_idea()
    local plan_content = project.read_file(project.plan_path) or ""
    plan_content = ensure_section_exists(plan_content, "ideas_section")
    local groups = group.get_groups(plan_content)
    vim.ui.input({prompt = loc.t("idea_name")}, function(idea_name)
        if not idea_name or idea_name == "" then return end
        vim.ui.select({loc.t("yes"), loc.t("no")}, {prompt = loc.t("use_llm")}, function(use_llm)
            local final_idea = idea_name
            if use_llm == loc.t("yes") then
                -- ToDo: final_idea = llm.improve_idea(idea_name)
            end
            local function add_idea(selected_groups)
                plan_content = project.add_item_to_section(plan_content, "ideas_section", final_idea)
                if selected_groups and #selected_groups > 0 then
                    for _, group_selected in ipairs(selected_groups) do
                        plan_content = project.add_item_to_section(plan_content, project.t("group_tag") .. ": " .. group_selected, final_idea)
                        plan_content = group.mark_ideas_as_grouped(plan_content, {final_idea}, group_selected)
                    end
                end
                project.write_file(project.plan_path, plan_content)
                project.commit_changes("Add idea: " .. idea_name)
                print(loc.t("idea_added") .. final_idea)
                vim.cmd("edit " .. project.plan_path)
                -- Posiciona el cursor en la idea recién agregada
                local idea_line = nil
                local lines = api.nvim_buf_get_lines(0, 0, -1, false)
                for i, line in ipairs(lines) do
                    if line:find(final_idea, 1, true) then
                        idea_line = i
                        break
                    end
                end
                if idea_line then
                    api.nvim_win_set_cursor(0, {idea_line, 0})
                end
                vim.cmd("normal! zz")
            end
            if #groups > 0 then
                multi_select(groups, {prompt = loc.t("add_to_group")}, function(selected)
                    add_idea(selected)
                end)
            else
                add_idea({})
            end
        end)
    end)
end

local function localized_group_tag(group_name)
    return "[" .. project.t("group_tag") .. ": " .. group_name .. "]"
end

local function clean_idea_text(idea_text)
    return idea_text:gsub("%s*%[" .. project.t("group_tag") .. ": [^%]]+%]", "")
end

local function extract_groups_from_idea(idea_text)
    local groups = {}
    for group in idea_text:gmatch("%[" .. project.t("group_tag") .. ": ([^%]]+)%]") do
        if group then
            groups[group] = true
        end
    end
    return groups
end

function M.sync_group_ideas_to_ideas()
    local buf = api.nvim_get_current_buf()
    local filename = api.nvim_buf_get_name(buf)
    if not filename:match("plan%.wyt%.md$") then return end

    local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
    local ideas_section, groups_info, ideas_set = {}, {}, {}
    local current_section = nil
    local current_group = nil
    
    -- Detectar secciones y recolectar ideas por grupo
    for i, line in ipairs(lines) do
        if line:match("^## " .. project.t("ideas_section")) then
            current_section = "ideas"
            current_group = nil
        elseif line:match("^## " .. project.t("group_tag") .. ": ") then
            current_section = "group"
            current_group = line:match("^## " .. project.t("group_tag") .. ": (.+)")
            if current_group then
                groups_info[current_group] = {}
            end
        elseif line:match("^## ") then
            current_section = nil
            current_group = nil
        elseif current_section == "ideas" and line:match("^%- ") then
            local idea = line:match("^%- (.+)")
            if idea then
                ideas_set[#ideas_set + 1] = clean_idea_text(idea)
                ideas_section[clean_idea_text(idea)] = {}
            end
        elseif current_section == "group" and line:match("^%- ") and current_group then
            local idea = line:match("^%- (.+)")
            if idea then
                groups_info[current_group][#groups_info[current_group] + 1] = clean_idea_text(idea)
            end
        end
    end  

    -- Add missing ideas to the ideas section and update group tags
    local changed = false
    for group_name, ideas in pairs(groups_info) do
        for _, idea in ipairs(ideas) do
            if ideas_section[idea] == nil and idea then
                -- add the idea to the ideas section
                ideas_set[#ideas_set + 1] = idea
                ideas_section[idea] = { [group_name] = true }
                changed = true
            elseif idea and ideas_section[idea] ~= nil and not ideas_section[idea][group_name] then
                ideas_section[idea][group_name] = true
                changed = true
            end
        end
    end

    -- update the ideas section in the file if changed
    if changed then
        local new_lines = {}
        local in_ideas_section = false
        for i, line in ipairs(lines) do
            if line:match("^## " .. project.t("ideas_section")) then
                in_ideas_section = true
                table.insert(new_lines, line)
                for _, idea in ipairs(ideas_set) do
                    local groups = ideas_section[idea] or {}
                    local group_tags = " "
                    for group_name, _ in pairs(groups) do
                        group_tags = group_tags .. localized_group_tag(group_name) .. " "
                    end
                    group_tags = group_tags:sub(1, -2) -- Remove trailing space
                    table.insert(new_lines, "- " .. idea .. group_tags)
                end
            elseif line:match("^## ") and in_ideas_section then
                in_ideas_section = false
                table.insert(new_lines, line)
            elseif not in_ideas_section or not line:match("^%- ") then
                table.insert(new_lines, line)
            end
        end
        api.nvim_buf_set_lines(buf, 0, -1, false, new_lines)
        print(loc.t("sync_complete"))
    end
end

return M