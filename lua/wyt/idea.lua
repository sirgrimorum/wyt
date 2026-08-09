local api = vim.api
local loc = require("wyt.localization")
local llm = require("wyt.llm")
local project = require("wyt.project")
local plan = require("wyt.plan")
local group = require("wyt.group")
local ui = require("wyt.ui")

local M = {}

local function ensure_section_exists(content, section)
    local section_header = "## " .. project.t(section)
    if not content:find(section_header) then
        return content .. "\n" .. section_header .. "\n"
    end
    return content
end

-- F12: was a module-level require (side effect at load time, crashed if telescope missing)
local function multi_select(...)
    return require("wyt.group").multi_select(...)
end

-- A section's plan is not the root plan; the orienting question differs there.
local function in_subsection()
    return project.section_plan_path ~= "" and project.section_plan_path ~= project.plan_path
end

-- P14: ask how to brainstorm, then collect one or more raw idea strings
local function show_guided_questions_and_proceed(callback)
    local types_mod = require("wyt.types")
    local project_type = project.get_project_type()
    local questions = types_mod.idea_questions(project_type, project.lang)

    -- Ask whether to enter free idea or answer questions one by one
    vim.ui.select(
        { loc.t("free_idea"), loc.t("answer_questions") },
        { prompt = loc.t("brainstorm_mode") },
        function(choice)
            if choice == loc.t("answer_questions") then
                -- Only this mode uses the full list, so only this mode shows it
                if #questions > 0 then
                    local hint = loc.t("guided_questions_title") .. project_type .. ":\n"
                    for i, q in ipairs(questions) do
                        hint = hint .. "  " .. i .. ". " .. q .. "\n"
                    end
                    vim.notify(hint, vim.log.levels.INFO)
                end
                -- Collect one idea per answered question
                local collected = {}
                local function ask_next(i)
                    if i > #questions then
                        callback(collected)
                        return
                    end
                    vim.ui.input({ prompt = loc.pad(questions[i] .. "\n" .. loc.t("question_prompt")) }, function(answer)
                        if answer and answer ~= "" then
                            table.insert(collected, answer)
                        end
                        ask_next(i + 1)
                    end)
                end
                ask_next(1)
            elseif choice == loc.t("free_idea") then
                -- Free-form: one idea, prompted by the type's single orienting
                -- question, or the generic prompt when the type defines none.
                local single = types_mod.idea_prompt(project_type, project.lang, in_subsection())
                vim.ui.input({ prompt = loc.pad(single or loc.t("idea_name")) }, function(idea_name)
                    if idea_name and vim.trim(idea_name) ~= "" then
                        callback({ vim.trim(idea_name) })
                    end
                end)
            end
        end
    )
end

-- Project context for the LLM: type plus the plan's Description section.
local function project_context(plan_content)
    local ctx = project.get_project_type()
    local header = "## " .. project.t("description_section")
    local start = plan_content:find(header, 1, true)
    if start then
        local rest = plan_content:sub(start + #header)
        local desc = rest:match("^(.-)\n## ") or rest
        desc = vim.trim((desc:gsub("%s+", " ")))
        if desc ~= "" then
            ctx = ctx .. ". " .. desc:sub(1, 400)
        end
    end
    return ctx
end

function M.new_idea()
    local plan_content = project.read_file(project.section_plan_path) or ""
    plan_content = ensure_section_exists(plan_content, "ideas_section")
    local groups = project.get_groups(plan_content)

    -- P14: guided questions flow; callback receives list of idea strings
    show_guided_questions_and_proceed(function(idea_names)
        if not idea_names or #idea_names == 0 then return end

        -- Improve one idea. The generated version is never applied silently:
        -- it is offered as a menu, and a genuine ambiguity comes back as a
        -- pickable question. Any failure mode falls back to the user's text.
        local MAX_QUESTIONS = 2
        local function improve_with_review(idea_name, on_done)
            local answers = {}
            local no_more_questions = false
            local request

            local function present(text)
                local keep  = loc.t("keep_result")
                local edit  = loc.t("edit_result")
                local again = loc.t("try_again")
                local mine  = loc.t("keep_mine")
                -- The generated sentence is too long for a select prompt, which
                -- renders on one line; it goes in a panel and the prompt keeps a
                -- short title. Without a float, fall back to the inline prompt.
                local panel = ui.preview(loc.t("llm_result_title"), text)
                local prompt = panel and loc.t("llm_result_action")
                    or (loc.t("llm_result_title") .. ": " .. text)
                vim.ui.select({ keep, edit, again, mine },
                    { prompt = prompt },
                    function(choice)
                        ui.close(panel)
                        if choice == keep then
                            on_done(text)
                        elseif choice == edit then
                            vim.ui.input({ prompt = loc.prompt("llm_review_idea"), default = text }, function(edited)
                                edited = edited and vim.trim(edited) or ""
                                on_done(edited ~= "" and edited or text)
                            end)
                        elseif choice == again then
                            request({ avoid = text })
                        else
                            -- "keep mine", or cancelled with <Esc>
                            on_done(idea_name)
                        end
                    end)
            end

            local function ask(question, options)
                local skip = loc.t("llm_skip_question")
                local items = vim.list_extend(vim.deepcopy(options), { skip })
                vim.ui.select(items, { prompt = question }, function(answer)
                    if not answer or answer == skip then
                        -- nothing more to tell it; demand an answer this time
                        no_more_questions = true
                        request({})
                        return
                    end
                    answers[#answers + 1] = { question = question, answer = answer }
                    request({})
                end)
            end

            request = function(extra)
                vim.notify(loc.t("llm_generating"), vim.log.levels.INFO)
                llm.improve_idea(idea_name, project.lang, function(res, err)
                    if err or not res then
                        vim.notify(loc.t("llm_error") .. (err or ""), vim.log.levels.WARN)
                        on_done(idea_name)
                        return
                    end
                    if res.kind == "question" then
                        ask(res.question, res.options)
                        return
                    end
                    if res.kind == "unusable" then
                        vim.notify(loc.t("llm_unusable_reply"), vim.log.levels.WARN)
                        on_done(idea_name)
                        return
                    end
                    -- Unstructured reply that is still a question: unanswerable
                    if llm.looks_like_question(res.text) and not llm.looks_like_question(idea_name) then
                        vim.notify(loc.t("llm_returned_question"), vim.log.levels.WARN)
                        on_done(idea_name)
                        return
                    end
                    present(res.text)
                end, {
                    context = project_context(plan_content),
                    answers = answers,
                    avoid = extra.avoid,
                    no_questions = no_more_questions or #answers >= MAX_QUESTIONS,
                })
            end

            request({})
        end

        -- Sequential: the review prompt for idea N must close before N+1 starts
        local function improve_all(list, i, acc, on_done)
            if i > #list then
                on_done(acc)
                return
            end
            improve_with_review(list[i], function(final)
                acc[#acc + 1] = final
                improve_all(list, i + 1, acc, on_done)
            end)
        end

        -- For each collected idea, optionally improve and add
        local function add_ideas_batch(ideas_list, selected_groups)
            for _, idea_name in ipairs(ideas_list) do
                if selected_groups and #selected_groups > 0 then
                    for _, group_selected in ipairs(selected_groups) do
                        plan_content = plan.add_item_to_section(plan_content, project.t("group_tag") .. ": " .. group_selected, idea_name)
                        if plan.is_group_tagged(plan_content, group_selected, "implemented") then
                            plan_content = project.mark_group_status(plan_content, group_selected, "edited")
                        end
                    end
                else
                    plan_content = plan.add_item_to_section(plan_content, project.t("ideas_section"), idea_name)
                end
            end
            project.write_file(project.section_plan_path, plan_content)
            project.commit_changes("Add ideas: " .. table.concat(ideas_list, ", "))
            vim.notify(loc.t("idea_added") .. table.concat(ideas_list, ", "), vim.log.levels.INFO)
            vim.cmd("e! " .. vim.fn.fnameescape(project.section_plan_path))
            -- Position cursor at last added idea
            local last_idea = ideas_list[#ideas_list]
            local lines = api.nvim_buf_get_lines(0, 0, -1, false)
            for i, line in ipairs(lines) do
                if line:find(last_idea, 1, true) then
                    api.nvim_win_set_cursor(0, {i, 0})
                    break
                end
            end
            vim.cmd("normal! zz")
        end

        local function ask_groups_and_add(final_ideas)
            local function add_idea(selected_groups)
                add_ideas_batch(final_ideas, selected_groups)
            end
            if #groups > 0 then
                multi_select(groups, { prompt = loc.t("add_to_group") }, add_idea)
            else
                add_idea({})
            end
        end

        -- Ask LLM improvement once for the whole batch
        vim.ui.select({ loc.t("yes"), loc.t("no") }, { prompt = loc.t("use_llm") }, function(use_llm)
            -- F15: improvement used to be skipped silently for batches of more
            -- than one idea; every collected idea is offered now.
            if use_llm == loc.t("yes") then
                improve_all(idea_names, 1, {}, ask_groups_and_add)
            else
                ask_groups_and_add(idea_names)
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
                current_group = project.clean_group_name(current_group)
                groups_info[current_group] = {}
            end
        elseif line:match("^## ") then
            current_section = nil
            current_group = nil
        elseif current_section == "ideas" and line:match("^%- ") then
            local idea = line:match("^%- (.+)")
            if idea then
                ideas_set[#ideas_set + 1] = clean_idea_text(idea)
                ideas_section[clean_idea_text(idea)] = extract_groups_from_idea(idea)
            end
        elseif current_section == "group" and line:match("^%- ") and current_group then
            local idea = line:match("^%- (.+)")
            if idea then
                groups_info[current_group][#groups_info[current_group] + 1] = clean_idea_text(idea)
            end
        end
    end  

    -- Add missing ideas to the ideas section and update group tags
    local updated_groups = {}
    local changed = false
    for group_name, ideas in pairs(groups_info) do
        for _, idea in ipairs(ideas) do
            if ideas_section[idea] == nil and idea then
                -- add the idea to the ideas section
                ideas_set[#ideas_set + 1] = idea
                ideas_section[idea] = { [group_name] = true }
                changed = true
                updated_groups[group_name] = true
            elseif idea and ideas_section[idea] ~= nil and not ideas_section[idea][group_name] then
                ideas_section[idea][group_name] = true
                changed = true
                updated_groups[group_name] = true
            end
        end
        for _, idea in ipairs(ideas_set) do
            local groups = ideas_section[idea] or {}
            for group_name, _ in pairs(groups) do
                if not groups_info[group_name] or #groups_info[group_name] == 0 or not vim.tbl_contains(groups_info[group_name], idea) then
                   ideas_section[idea][group_name] = nil
                   changed = true
                   if groups_info[group_name] then
                       updated_groups[group_name] = true
                   end
                end
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
                -- Revisar si es un grupo que ha cambiado y si tiene el tag "implemented" poner el tag "edited"
                for group_name, _ in pairs(updated_groups) do
                    if line:match("^## " .. project.t("group_tag") .. ": " .. group_name) then
                        line = line:gsub("%s*%[[^%]]+%]", " [" .. project.t("edited") .. "]")
                    end
                end
                table.insert(new_lines, line)
            elseif not in_ideas_section or not line:match("^%- ") then
                table.insert(new_lines, line)
            end
        end
        api.nvim_buf_set_lines(buf, 0, -1, false, new_lines)
        -- O6: vim.notify instead of print
        vim.notify(loc.t("sync_complete"), vim.log.levels.INFO)
    end
end

local function find_section_bounds(lines, cursor)
    local section_start, section_end = nil, nil
    for i = cursor, 1, -1 do
        if lines[i]:match("^## ") then
            section_start = i
            break
        end
    end
    for i = cursor + 1, #lines do
        if lines[i]:match("^## ") then
            section_end = i - 1
            break
        end
    end
    section_end = section_end or #lines
    return section_start, section_end
end

function M.move_idea(direction)
    local buf = api.nvim_get_current_buf()
    local cursor = api.nvim_win_get_cursor(0)[1]
    local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
    local section_start, section_end = find_section_bounds(lines, cursor)
    if not section_start or not section_end then return end

    -- Busca la idea actual
    local idx = cursor
    if not lines[idx]:match("^%- ") then return end

    local target_idx = direction == "up" and idx - 1 or idx + 1
    if target_idx < section_start + 1 or target_idx > section_end then return end
    if not lines[target_idx]:match("^%- ") then return end

    -- Intercambia las líneas
    lines[idx], lines[target_idx] = lines[target_idx], lines[idx]
    -- Actualiza el estado del grupo si es necesario
    local section_line = lines[section_start]
    if section_line and section_line:match("^## " .. project.t("group_tag") .. ": ") then
        -- Reemplaza cualquier tag [implemented] o [edited] por el nuevo tag [edited]
        section_line = section_line:gsub("%s*%[[^%]]+%]", " [" .. project.t("edited") .. "]")
        lines[section_start] = section_line
    end

    api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    api.nvim_win_set_cursor(0, {target_idx, 0})
end

return M