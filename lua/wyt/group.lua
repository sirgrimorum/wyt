local api = vim.api
local loc = require("wyt.localization")
local project = require("wyt.project")
local plan = require("wyt.plan")
local types = require("wyt.types")
local ui = require("wyt.ui")

local M = {}

local function rename_group(content, old_name, new_name)
    local old_header = "## " .. vim.pesc(project.t("group_tag")) .. ": " .. vim.pesc(old_name)
    local new_header = "## " .. project.t("group_tag") .. ": " .. new_name
    local old_group_marker = "%[" .. vim.pesc(project.t("group_tag")) .. ": " .. vim.pesc(old_name) .. "%]"
    local new_group_marker = "[" .. project.t("group_tag") .. ": " .. new_name .. "]"

    local new_content = content:gsub(old_group_marker, new_group_marker)
    return new_content:gsub(vim.pesc(old_header), new_header)
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
                local existing = {}
                for tag in line:gmatch("%[" .. project.t("group_tag") .. ": [^%]]+%]") do
                    table.insert(existing, tag)
                end
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
    -- O7: removed vim.cmd("write"), read from open buffer instead of forcing a save
    local plan_content
    for _, buf in ipairs(api.nvim_list_bufs()) do
        if api.nvim_buf_is_loaded(buf) and api.nvim_buf_get_name(buf) == project.section_plan_path then
            local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
            plan_content = table.concat(lines, "\n")
            break
        end
    end
    plan_content = plan_content or project.read_file(project.section_plan_path) or ""

    local ideas = project.get_ideas(plan_content, "## " .. project.t("ideas_section"))
    if #ideas == 0 then
        -- O6: vim.notify instead of print
        vim.notify(loc.t("no_ideas"), vim.log.levels.WARN)
        return
    end
    local groups = project.get_groups(plan_content)
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
            -- silent: the file message from :edit, stacked on the confirmation,
            -- overflows the command line into a "Press ENTER" prompt
            vim.cmd("silent edit! " .. vim.fn.fnameescape(project.section_plan_path))  -- F5
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
            local llm = require("wyt.llm")
            local project_type = project.get_project_type()
            -- P14: one orienting question, used as the prompt for the name.
            -- The numbered list of group questions made no sense here: the
            -- writer names one group, they do not answer each question in turn.
            -- Raw, not padded: ui.ask_input pads whichever of the question or
            -- the short title ends up on the prompt line. Inside a section with
            -- an archetype, the archetype names the group: a Characters section
            -- asks which character this is.
            local kind = project.get_section_kind()
            local question = types.group_prompt(project_type, project.lang, kind)
                or types.group_name_hint(project_type, project.lang, kind)

            local function create_with(name)
                name = name and vim.trim(name) or ""
                if name == "" then return end
                local updated_content = plan_content
                for _, idea in ipairs(selected_ideas) do
                    updated_content = plan.add_item_to_section(updated_content, project.t("group_tag") .. ": " .. name, idea)
                end
                updated_content = M.mark_ideas_as_grouped(updated_content, selected_ideas, name)
                project.write_file(project.section_plan_path, updated_content)
                project.commit_changes("Created group: " .. name)
                vim.notify(ui.fit_message(loc.t("group_created"), name), vim.log.levels.INFO)
                finish(name)
            end

            -- Both branches ask the same question; the LLM one only pre-fills
            -- the answer, so the suggestion is edited in place or accepted.
            local function ask_name(suggested)
                ui.ask_input({
                    title = loc.t("group_name_title"),
                    question = question,
                    default = suggested,
                }, function(name)
                    if name == nil then return end -- <Esc>: no group
                    if vim.trim(name) == "" and suggested then
                        name = suggested
                    end
                    create_with(name)
                end)
            end

            vim.ui.select({ loc.t("yes"), loc.t("no") }, { prompt = loc.t("use_llm") }, function(use_llm)
                if use_llm == loc.t("yes") and #selected_ideas > 0 then
                    vim.notify(loc.t("llm_generating"), vim.log.levels.INFO)
                    -- The model is given the type's name, not its id: "un grupo
                    -- de ideas de un long_novel" is half English and misspelt.
                    local type_label = types.label(project_type, project.lang)
                    llm.suggest_group_name(selected_ideas, type_label, project.lang, function(suggested, err)
                        if err then vim.notify(loc.t("llm_error") .. err, vim.log.levels.WARN) end
                        -- A name that is really a question is no name at all
                        if suggested and suggested ~= "" and llm.looks_like_question(suggested) then
                            vim.notify(loc.t("llm_returned_question"), vim.log.levels.WARN)
                            suggested = nil
                        end
                        ask_name(suggested ~= "" and suggested or nil)
                    end)
                else
                    ask_name(nil)
                end
            end)
        end
        if #groups > 0 then
            vim.ui.select({loc.t("add_to_existing_group"), loc.t("create_new_group")}, {prompt = loc.t("group_action")}, function(action)
                if action == loc.t("add_to_existing_group") then
                    vim.ui.select(groups, {prompt = loc.t("select_group")}, function(group_name)
                        if group_name then
                            local rename_q = loc.t("edit_group_name") .. " [" .. group_name .. "]:"
                            ui.ask_input({
                                title = loc.t("group_name_title"),
                                question = rename_q,
                            }, function(new_name)
                                if new_name == nil then return end -- <Esc>: add nothing
                                local final_name = new_name ~= "" and new_name or group_name
                                local updated_content = rename_group(plan_content, group_name, final_name)
                                -- P4: rename section folder when group name changes
                                if final_name ~= group_name then
                                    -- The folder as it is on disk, which for a
                                    -- section named before accents were folded is
                                    -- not what the new name slugifies to.
                                    local old_dir = project.group_dir(project.current_section_dir, group_name)
                                    local new_slug = project.slugify(final_name)
                                    old_dir = old_dir and old_dir:gsub("/$", "")
                                    local new_dir = project.current_section_dir .. new_slug
                                    if old_dir and new_slug ~= "" and old_dir ~= new_dir then
                                        vim.fn.rename(old_dir, new_dir)
                                        vim.notify("[WYT] Renamed section folder: "
                                            .. vim.fn.fnamemodify(old_dir, ":t") .. " → " .. new_slug, vim.log.levels.INFO)
                                    end
                                end
                                for _, idea in ipairs(selected_ideas) do
                                    updated_content = plan.add_item_to_section(updated_content, project.t("group_tag") .. ": " .. final_name, idea)
                                end
                                updated_content = M.mark_ideas_as_grouped(updated_content, selected_ideas, final_name)
                                project.write_file(project.section_plan_path, updated_content)
                                project.commit_changes("Grouped ideas in: " .. final_name)
                                -- O6: vim.notify instead of print
                                vim.notify(loc.t("group_updated") .. final_name, vim.log.levels.INFO)
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
    -- The blank lines that follow a group belong to the gap between groups, not to
    -- the group itself. The last group in the file has none, so counting them in
    -- would make it swap as a shorter block and move the separator to the wrong side.
    while end_idx > start_idx and lines[end_idx]:match("^%s*$") do
        end_idx = end_idx - 1
    end
    return start_idx, end_idx
end

-- O8: extracted shared block-swap helper; eliminates duplicated logic in move_group up/down cases
-- Swaps two non-overlapping line ranges. a_start < b_start always.
local function swap_line_blocks(lines, a_start, a_end, b_start, b_end)
    local a_block, b_block = {}, {}
    for i = a_start, a_end do table.insert(a_block, lines[i]) end
    for i = b_start, b_end do table.insert(b_block, lines[i]) end
    local result = {}
    for i = 1, #lines do
        if i == a_start then
            for _, l in ipairs(b_block) do table.insert(result, l) end
        elseif i == b_start then
            for _, l in ipairs(a_block) do table.insert(result, l) end
        elseif (i > a_start and i <= a_end) or (i > b_start and i <= b_end) then
            -- skip: already inserted above
        else
            table.insert(result, lines[i])
        end
    end
    return result
end

function M.move_group(direction)
    local buf = api.nvim_get_current_buf()
    local cursor = api.nvim_win_get_cursor(0)[1]
    local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
    local start_idx, end_idx = find_group_bounds(lines, cursor)
    if not start_idx or not end_idx then return end

    local header_pat = "^## " .. project.t("group_tag") .. ": "
    local target_start, target_end

    if direction == "up" then
        for i = start_idx - 1, 1, -1 do
            if lines[i]:match(header_pat) then
                target_start, target_end = find_group_bounds(lines, i)
                break
            elseif lines[i]:match("^## " .. project.t("ideas_section")) then
                return  -- do not move above Ideas section
            end
        end
        if not target_start then return end
        -- O8: use shared helper; target is above current, so target=a, current=b
        local new_lines = swap_line_blocks(lines, target_start, target_end, start_idx, end_idx)
        api.nvim_buf_set_lines(buf, 0, -1, false, new_lines)
        api.nvim_win_set_cursor(0, {target_start, 0})
    else
        local next_idx = end_idx + 1
        while next_idx <= #lines do
            if lines[next_idx]:match(header_pat) then
                target_start, target_end = find_group_bounds(lines, next_idx)
                break
            elseif lines[next_idx]:match("^## ") then
                return  -- do not move below another section
            end
            next_idx = next_idx + 1
        end
        if not target_start then return end
        -- O8: use shared helper; current is above target, so current=a, target=b
        local new_lines = swap_line_blocks(lines, start_idx, end_idx, target_start, target_end)
        api.nvim_buf_set_lines(buf, 0, -1, false, new_lines)
        -- The target block and the untouched gap now sit before the moved group:
        -- start_idx + (target size) + (gap size) collapses to start_idx + target_end - end_idx.
        api.nvim_win_set_cursor(0, {start_idx + target_end - end_idx, 0})
    end
end

return M
