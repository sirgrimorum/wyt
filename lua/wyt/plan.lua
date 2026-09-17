local api = vim.api
local project = require("wyt.project")
local loc = require("wyt.localization")
local ui = require("wyt.ui")

local M = {}

local function get_config_sections(section_dir)
    local config_path = section_dir .. "config.wyt.yml"
    local config_content = project.read_file(config_path)
    return project.config_value(config_content, "sections") == "true"
end

local function get_group_tags(line)
    local tags = {}
    for tag in line:gmatch("%[" .. project.t("group_tag") .. ": ([^%]]+)%]") do
        table.insert(tags, tag)
    end
    return tags
end

local function get_group_tag_at_cursor(line, col)
    local pattern = "%[" .. project.t("group_tag") .. ": ([^%]]+)%]"
    local start = 1
    while true do
        local s, e, tag = line:find(pattern, start)
        if not s then break end
        if col >= s and col <= e then
            return tag
        end
        start = e + 1
    end
    return nil
end

-- Detecta si el grupo está marcado con un tag específico
function M.is_group_tagged(content, group_name, tag)
    if not content then return false end
    local escaped_group_name = group_name:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
    local group_pat = "## " .. project.t("group_tag") .. ": " .. escaped_group_name .. "%s*%[" .. project.t(tag) .. "%]"
    return content:match(group_pat)
end

-- Pregunta si se debe re-implementar el grupo
local function prompt_reimplement_group(current_plan_content, group_name, section_dir, sections_enabled, section_plan)
    -- The group name is the writer's own sentence-long text often enough that
    -- the question outgrows a prompt; ask_select moves it into a panel then.
    local question = loc.t("the_group") .. " '" .. group_name .. "' " .. loc.t("is_edited")
    ui.ask_select({
        title = loc.t("group_edited_title"),
        question = question,
        prompt = loc.t("reimplement"),
    }, { loc.t("yes"), loc.t("no") }, function(choice)
        local function open()
            ui.open_file(section_plan)
        end
        if choice == loc.t("yes") then
            -- A fresh section asks what it holds, so the file is only there to
            -- open once implement_group says so.
            project.implement_group(current_plan_content, group_name, section_dir, sections_enabled, open)
        else
            open()
        end
    end)
end

function M.goto_wyt_tab()
    local buf = api.nvim_get_current_buf()
    local filename = api.nvim_buf_get_name(buf)
    if not filename:match("plan%.wyt%.md$") then return end

    local cursor = api.nvim_win_get_cursor(0)[1]
    local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
    local current_plan_content = table.concat(lines, "\n")
    local line = lines[cursor]
    if not line then return end

    local current_section_dir = project.get_section_dir()
    local sections_enabled = get_config_sections(current_section_dir)
    local group_pat = "^## " .. project.t("group_tag") .. ": (.+)"
    local idea_pat = "^%- (.+)"
    local group_tag_pat = "%[" .. project.t("group_tag") .. ": ([^%]]+)%]"
    
    local group_name = nil

    local function goto_group_name()
        group_name = project.clean_group_name(group_name)
        if sections_enabled then
            local slug = project.slugify(group_name)
            -- An empty slug would point the section at its own folder and
            -- reopen this very plan. implement_group says why and stops.
            if slug == "" then
                return project.implement_group(current_plan_content, group_name, current_section_dir, sections_enabled, function() end)
            end
            -- The folder already on disk when there is one, so a section named
            -- before accents were folded is opened instead of offered again.
            local existing = project.group_dir(current_section_dir, group_name)
            local section_plan = (existing or (current_section_dir .. slug .. "/")) .. "plan.wyt.md"
            local function open()
                ui.open_file(section_plan)
            end
            -- O4: fs_stat instead of vim.fn.filereadable
            if not (vim.uv or vim.loop).fs_stat(section_plan) then
                -- O6: vim.notify instead of print
                vim.notify(loc.t("goto_no_section_plan") .. ": " .. section_plan, vim.log.levels.INFO)
                vim.notify(loc.t("implementing") .. "'" .. group_name .. "'...", vim.log.levels.INFO)
                -- The section is created behind a question now, so the tab waits
                -- for it: nothing to open if the writer cancels.
                project.implement_group(current_plan_content, group_name, current_section_dir, sections_enabled, open)
            else
                if M.is_group_tagged(current_plan_content, group_name, "edited") then
                    prompt_reimplement_group(current_plan_content, group_name, current_section_dir, sections_enabled, section_plan)
                    return
                elseif not M.is_group_tagged(current_plan_content, group_name, "implemented") then
                    vim.notify(loc.t("the_group") .. " '" .. group_name .. "' " .. loc.t("is_not_implemented"), vim.log.levels.INFO)
                    vim.notify(loc.t("implementing") .. "'" .. group_name .. "'...", vim.log.levels.INFO)
                    project.implement_group(current_plan_content, group_name, current_section_dir, sections_enabled, open)
                    return
                end
                open()
            end
        else
            -- F6: removed extra leading slash (current_section_dir already ends with /)
            local text_path = current_section_dir .. "text.wyt.md"
            local function open()
                ui.open_file(text_path)
                -- P5: position cursor at the group section in text.wyt.md
                local group_header = "## " .. project.t("group_tag") .. ": " .. group_name
                for i, tline in ipairs(api.nvim_buf_get_lines(0, 0, -1, false)) do
                    if tline:find(group_header, 1, true) then
                        api.nvim_win_set_cursor(0, {i, 0})
                        vim.cmd("normal! zz")
                        break
                    end
                end
            end
            -- O4: fs_stat instead of vim.fn.filereadable
            if not (vim.uv or vim.loop).fs_stat(text_path) then
                -- O6: vim.notify instead of print
                vim.notify(loc.t("goto_no_section_text") .. ": " .. text_path, vim.log.levels.INFO)
                vim.notify(loc.t("implementing") .. "'" .. group_name .. "'...", vim.log.levels.INFO)
                project.implement_group(current_plan_content, group_name, current_section_dir, sections_enabled, open)
            else
                if M.is_group_tagged(current_plan_content, group_name, "edited") then
                    prompt_reimplement_group(current_plan_content, group_name, current_section_dir, sections_enabled, text_path)
                    return
                elseif not M.is_group_tagged(current_plan_content, group_name, "implemented") then
                    vim.notify(loc.t("the_group") .. " '" .. group_name .. "' " .. loc.t("is_not_implemented"), vim.log.levels.INFO)
                    vim.notify(loc.t("implementing") .. "'" .. group_name .. "'...", vim.log.levels.INFO)
                    project.implement_group(current_plan_content, group_name, current_section_dir, sections_enabled, open)
                    return
                end
                open()
            end
        end
    end

    local function find_header_name_above(lines, idx, header_pat)
        for i = idx - 1, 1, -1 do
            local header_name = lines[i]:match(header_pat)
            if header_name then
                return header_name
            end
            -- Si encuentras otro encabezado (por ejemplo, "## " pero no de header_pat), detén la búsqueda
            if lines[i]:match("^## ") and not lines[i]:match(header_pat) then
                break
            end
        end
        return nil
    end

    -- Si es un grupo
    group_name = line:match(group_pat)
    if group_name then
        goto_group_name()
        return
    end

    -- Si es una idea dentro de un grupo
    group_name = find_header_name_above(lines, cursor, group_pat)
    if line:match(idea_pat) and group_name then
        goto_group_name()
        return
    end

    -- Si es una idea en la sección de ideas
    local idea_name = find_header_name_above(lines, cursor, "^## " .. project.t("ideas_section"))
    if line:match(idea_pat) and idea_name then
        local col = api.nvim_win_get_cursor(0)[2] + 1 -- F3: was undeclared global
        group_name = get_group_tag_at_cursor(line, col)
        if group_name then
            goto_group_name()
            return
        end
        -- Si no hay grupo y no hay secciones, navega al texto
        if not sections_enabled then
            local text_path = current_section_dir .. "text.wyt.md"
            -- O4: fs_stat; O6: vim.notify
            if (vim.uv or vim.loop).fs_stat(text_path) then
                ui.open_file(text_path)
                -- P5: position cursor at the idea placeholder in text.wyt.md
                local idea_text = line:sub(3)  -- strip "- " prefix
                for i, tline in ipairs(api.nvim_buf_get_lines(0, 0, -1, false)) do
                    if tline:find(idea_text, 1, true) then
                        api.nvim_win_set_cursor(0, {i, 0})
                        vim.cmd("normal! zz")
                        break
                    end
                end
            else
                vim.notify(loc.t("goto_no_section_text") .. ": " .. text_path, vim.log.levels.WARN)
            end
        end
        return
    end

    -- P6: on the document title (# heading), navigate to the parent plan if one exists
    if line:match("^# ") then
        local parent = current_section_dir:match("^(.*[\\/])[^\\/]+[\\/]$")
        if parent then
            local parent_plan = parent .. "plan.wyt.md"
            if (vim.uv or vim.loop).fs_stat(parent_plan) then
                ui.open_file(parent_plan)
            end
        end
    end
end

function M.add_item_to_section(content, section, item)
    -- Eliminar cualquier \n del item
    item = item:gsub("\n", "")
    -- F10: `section` is now raw header text (already translated by caller), not a translation key
    local section_header = "## " .. section
    -- Plain find, not a pattern: a group called "Cap (1)" or "Nota-2" carries
    -- pattern magic, so the header was looked for somewhere else or nowhere at
    -- all, and the miss appended a second section with the same name.
    local section_start = content:find(section_header, 1, true)
    if section_start then
        local next_section = content:find("\n## ", section_start + #section_header, true)
        local section_end = next_section and (next_section - 1) or #content
        local section_content = content:sub(section_start, section_end)
        local before = content:sub(1, section_start - 1)
        local after = content:sub(section_end + 1)
        -- Busca el último ítem en la sección
        local last_item_pos = 0
        for pos in section_content:gmatch("()\n%- *") do
            last_item_pos = pos
        end
        local before_item = ""
        local after_item = ""
        if last_item_pos > 0 then
            -- Busca el salto de línea después del último ítem
            local next_newline = section_content:find("\n", last_item_pos + 2) or (#before + 1)
            before_item = section_content:sub(1, next_newline - 1)
            after_item = section_content:sub(next_newline)
        else
            -- Si no hay ítems, agrega luego del header de section
            before_item = section_content:sub(1, #section_header)
            after_item = section_content:sub(#section_header + 1)
        end
        return before .. before_item .. "\n- " .. item .. after_item .. after
    else
        return content .. "\n\n" .. section_header .. "\n- " .. item
    end
end

return M