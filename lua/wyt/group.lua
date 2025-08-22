local api = vim.api
local loc = require("wyt.localization")
local project = require("wyt.project")
local plan = require("wyt.plan")

local M = {}

local function get_ideas(plan_content)
    local ideas = {}
    local section_header = "## Ideas"
    local start = plan_content:find(section_header)
    if not start then return ideas end
    local next_section = plan_content:find("\n## ", start + #section_header)
    local ideas_block = next_section and plan_content:sub(start + #section_header, next_section - 1) or plan_content:sub(start + #section_header)
    for idea in ideas_block:gmatch("%- ([^\n]+)") do
        -- Elimina cualquier tag de grupo al final de la idea
        local clean_idea = idea:gsub("%s*%[" .. project.t("group_tag") .. ": [^%]]+%]", "")
        table.insert(ideas, clean_idea)
    end
    return ideas
end

function M.get_groups(plan_content)
    local groups = {}
    local group_header = "## " .. project.t("group_tag") .. ": "
    for group in plan_content:gmatch(group_header .. "([^\n]+)") do
        table.insert(groups, group)
    end
    return groups
end

local function escape_pattern(text)
    return text:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
end

local function rename_group(content, old_name, new_name)
    local old_header = "## " .. escape_pattern(project.t("group_tag")) .. ": " .. escape_pattern(old_name)
    local new_header = "## " .. project.t("group_tag") .. ": " .. new_name
    local old_group_marker = "%[" .. escape_pattern(project.t("group_tag")) .. ": " .. escape_pattern(old_name) .. "%]"
    local new_group_marker = "[" .. project.t("group_tag") .. ": " .. new_name .. "]"

    local new_content = content:gsub(old_group_marker, new_group_marker)
    return new_content:gsub(escape_pattern(old_header), new_header)
end

function M.mark_ideas_as_grouped(content, ideas, group_name)
    local group_tag = "[" .. project.t("group_tag") .. ": " .. group_name .. "]"

    local section_header = "## " .. project.t("ideas_section")
    local start = content:find(section_header)
    if not start then return content end
    local next_section = content:find("\n## ", start + #section_header)
    local before = content:sub(1, start + #section_header)
    local ideas_block = next_section and content:sub(start + #section_header + 1, next_section - 1) or content:sub(start + #section_header + 1)
    local after = next_section and content:sub(next_section) or ""
    local updated_block = {}
    for line in ideas_block:gmatch("[^\n]+") do
        local idea_text = line:match("%- (.+)")
        if idea_text then
            local is_selected = false
            for _, sel in ipairs(ideas) do
                if idea_text:find(sel, 1, true) then
                    is_selected = true
                    break
                end
            end
            if is_selected then
                -- Elimina anotaciones previas y agrega la nueva (soporta múltiples grupos)
                local existing = {}
                for tag in line:gmatch("%[" .. project.t("group_tag") .. ": [^%]]+%]") do
                    table.insert(existing, tag)
                end
                -- Evita duplicados
                local already = false
                for _, tag in ipairs(existing) do
                    if tag == group_tag then already = true end
                end
                line = line:gsub("%[" .. project.t("group_tag") .. ": [^%]]+%]", "")
                if #existing > 0 then
                    for _, tag in ipairs(existing) do
                        line = line .. " " .. tag
                    end
                end
                if not already then
                    line = line .. " " .. group_tag
                end
            end
        end
        table.insert(updated_block, line)
    end
    return before .. table.concat(updated_block, "\n") .. "\n" .. after
end

function M.multi_select(items, opts, callback)
    local pickers = require('telescope.pickers')
    local finders = require('telescope.finders')
    local conf = require('telescope.config').values
    local actions = require('telescope.actions')
    local action_state = require('telescope.actions.state')

    local selected = opts and opts.preselected or {}

    local function make_display_list()
        local display = {}
        for _, item in ipairs(items) do
            if vim.tbl_contains(selected, item) then
                table.insert(display, "[x] " .. item)
            else
                table.insert(display, "[ ] " .. item)
            end
        end
        return display
    end

    local function get_original_item(display_item)
        return display_item:sub(5)
    end

    local picker
    picker = pickers.new({}, {
        prompt_title = opts and opts.prompt or "Selecciona elementos",
        finder = finders.new_table {
            results = make_display_list()
        },
        sorter = conf.generic_sorter({}),
        attach_mappings = function(prompt_bufnr, map)
            local function toggle_selection()
                local entry = action_state.get_selected_entry()
                if entry then
                    local item = get_original_item(entry.value)
                    if not vim.tbl_contains(selected, item) then
                        table.insert(selected, item)
                    else
                        for i, v in ipairs(selected) do
                            if v == item then
                                table.remove(selected, i)
                                break
                            end
                        end
                    end
                    picker:refresh(finders.new_table { results = make_display_list() }, {reset_prompt = false})
                end
            end

            map('i', '<Tab>', function()
                toggle_selection()
                actions.move_selection_next(prompt_bufnr)
            end)
            map('i', '<S-Tab>', function()
                toggle_selection()
                actions.move_selection_previous(prompt_bufnr)
            end)
            actions.select_default:replace(function()
                actions.close(prompt_bufnr)
                callback(selected)
            end)
            return true
        end,
    })
    picker:find()
end

function M.new_group(line1, line2)
    -- Guardar los cambios del buffer antes de comenzar
    vim.cmd("write")
    local plan_content = project.read_file(project.plan_path) or ""
    local ideas = get_ideas(plan_content)
    if #ideas == 0 then
        print(loc.t("no_ideas"))
        return
    end
    local groups = M.get_groups(plan_content)
    local selected_ideas = {}

    local function insert_selected_idea(idea)
        if idea and idea ~= "" then
            local clean_idea = idea:gsub("%s*%[" .. project.t("group_tag") .. ": [^%]]+%]", "")
            for _, existing_idea in ipairs(ideas) do
                if existing_idea == clean_idea then
                    table.insert(selected_ideas, clean_idea)
                    break
                end
            end
        end
    end

    -- Procesa el rango si existe
    if line1 and line2 and line1 ~= 0 and line2 ~= 0 then
        if line1 > line2 then line1, line2 = line2, line1 end
        local lines = api.nvim_buf_get_lines(0, line1 - 1, line2, false)
        for _, line in ipairs(lines) do
            local idea = line:match("%- (.+)")
            insert_selected_idea(idea)
        end
    else
        local cursor_line = api.nvim_win_get_cursor(0)[1]
        local line = api.nvim_buf_get_lines(0, cursor_line - 1, cursor_line, false)[1]
        local idea = line and line:match("%- (.+)")
        insert_selected_idea(idea)
    end

    local function proceed_group()
        local function finish(group_name)
            vim.cmd("e! " .. project.plan_path)
            if group_name and group_name ~= "" then
                local group_header = "## " .. project.t("group_tag") .. ": " .. group_name
                local lines = api.nvim_buf_get_lines(0, 0, -1, false)
                local target_line = nil
                for i, line in ipairs(lines) do
                    if line:find(group_header, 1, true) then
                        target_line = i
                        break
                    end
                end
                if target_line then
                    api.nvim_win_set_cursor(0, {target_line, 0})
                end
            end
            vim.cmd("normal! zz")
        end
        local function new_group_name()
            vim.ui.input({prompt = loc.t("new_group_name")}, function(name)
                if not name or name == "" then return end
                local updated_content = plan_content
                for _, idea in ipairs(selected_ideas) do
                    updated_content = plan.add_item_to_section(updated_content, project.t("group_tag") .. ": " .. name, idea)
                end
                updated_content = M.mark_ideas_as_grouped(updated_content, selected_ideas, name)
                project.write_file(project.plan_path, updated_content)
                project.commit_changes("Created group: " .. name)
                print(loc.t("group_created") .. name)
                finish(name)
            end)
        end
        if #groups > 0 then
            vim.ui.select({loc.t("add_to_existing_group"), loc.t("create_new_group")}, {prompt = loc.t("group_action")}, function(action)
                if action == loc.t("add_to_existing_group") then
                    -- ToDo: Revisar
                    vim.ui.select(groups, {prompt = loc.t("select_group")}, function(group_name)
                        if group_name then 
                            vim.ui.input({prompt = loc.t("edit_group_name") .. " [" .. group_name .. "]: "}, function(new_name)
                                local final_name = new_name and new_name ~= "" and new_name or group_name
                                local updated_content = rename_group(plan_content, group_name, final_name)
                                for _, idea in ipairs(selected_ideas) do
                                    updated_content = plan.add_item_to_section(updated_content, project.t("group_tag") .. ": " .. final_name, idea)
                                end
                                updated_content = M.mark_ideas_as_grouped(updated_content, selected_ideas, final_name)
                                project.write_file(project.plan_path, updated_content)
                                project.commit_changes("Grouped ideas in: " .. final_name)
                                print(loc.t("group_updated") .. final_name)
                                finish(final_name)
                            end)
                        else
                            finish(nil)
                        end
                    end)
                else
                    new_group_name()
                end
            end)
        else
            new_group_name()
        end
    end
    if #selected_ideas == 0 then
        M.multi_select(ideas, {prompt = loc.t("select_ideas")}, function(selected)
            if not selected or #selected == 0 then return end
            selected_ideas = selected
            proceed_group()
        end)
    else
        M.multi_select(ideas, {prompt = loc.t("add_more_ideas"), preselected = selected_ideas}, function(more_selected)
            if more_selected and #more_selected > 0 then
                selected_ideas = more_selected
            end
            proceed_group()
        end)
    end

end

local function find_group_bounds(lines, cursor)
    local header_pat = "^## " .. project.t("group_tag") .. ": "
    if not lines[cursor]:match(header_pat) then return nil end

    local start_idx = cursor
    local end_idx = cursor
    for i = cursor + 1, #lines do
        if lines[i]:match("^## ") then
            end_idx = i - 1
            break
        end
        end_idx = i
    end
    return start_idx, end_idx
end

function M.move_group(direction)
    local buf = api.nvim_get_current_buf()
    local cursor = api.nvim_win_get_cursor(0)[1]
    local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
    local start_idx, end_idx = find_group_bounds(lines, cursor)
    if not start_idx or not end_idx then return end

    -- Busca el grupo anterior/siguiente
    local header_pat = "^## " .. project.t("group_tag") .. ": "
    local target_start, target_end
    if direction == "up" then
        -- Busca el grupo anterior
        for i = start_idx - 1, 1, -1 do
            if lines[i]:match(header_pat) then
                target_start, target_end = find_group_bounds(lines, i)
                break
            elseif lines[i]:match("^## " .. project.t("ideas_section")) then
                -- No permitir pasar por encima de Ideas
                return
            end
        end
        if not target_start then return end
        -- Intercambia los bloques
        local group_block = {}
        for i = start_idx, end_idx do table.insert(group_block, lines[i]) end
        local target_block = {}
        for i = target_start, target_end do table.insert(target_block, lines[i]) end
        local new_lines = {}
        for i = 1, #lines do
            if i == target_start then
                for _, l in ipairs(group_block) do table.insert(new_lines, l) end
            elseif i == start_idx then
                for _, l in ipairs(target_block) do table.insert(new_lines, l) end
            elseif i > target_start and i <= target_end then
                -- skip target block
            elseif i > start_idx and i <= end_idx then
                -- skip current block
            else
                table.insert(new_lines, lines[i])
            end
        end
        api.nvim_buf_set_lines(buf, 0, -1, false, new_lines)
        api.nvim_win_set_cursor(0, {target_start, 0})
    else
        -- Busca el grupo siguiente
        local next_idx = end_idx + 1
        while next_idx <= #lines do
            if lines[next_idx]:match(header_pat) then
                target_start, target_end = find_group_bounds(lines, next_idx)
                break
            elseif lines[next_idx]:match("^## ") then
                -- No permitir pasar por debajo de otra sección
                return
            end
            next_idx = next_idx + 1
        end
        if not target_start then return end
        -- Intercambia los bloques
        local group_block = {}
        for i = start_idx, end_idx do table.insert(group_block, lines[i]) end
        local target_block = {}
        for i = target_start, target_end do table.insert(target_block, lines[i]) end
        local new_lines = {}
        for i = 1, #lines do
            if i == start_idx then
                for _, l in ipairs(target_block) do table.insert(new_lines, l) end
            elseif i == target_start then
                for _, l in ipairs(group_block) do table.insert(new_lines, l) end
            elseif i > start_idx and i <= end_idx then
                -- skip current block
            elseif i > target_start and i <= target_end then
                -- skip target block
            else
                table.insert(new_lines, lines[i])
            end
        end
        api.nvim_buf_set_lines(buf, 0, -1, false, new_lines)
        api.nvim_win_set_cursor(0, {start_idx + #target_block, 0})
    end
end

return M