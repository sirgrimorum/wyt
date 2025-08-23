local api = vim.api
local project = require("wyt.project")
local loc = require("wyt.localization")

local M = {}

local function get_config_sections(section_dir)
    local config_path = section_dir .. "config.wyt.yml"
    local config_content = project.read_file(config_path)
    return config_content and config_content:match("sections:%s*true") ~= nil
end

local function slugify(str)
    local new_str = str
    return new_str:lower():gsub("%s+", "-"):gsub("[^%w%-]", "")
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
    vim.ui.select({loc.t("yes"), loc.t("no")}, {prompt = loc.t("the_group") .. " '" .. group_name .. "' " .. loc.t("is_edited")}, function(choice)
        if choice == loc.t("yes") then
            project.implement_group(current_plan_content, group_name, section_dir, sections_enabled)
        end
        vim.cmd("tabnew " .. section_plan)
    end)
end

function M.clean_group_name(name)
    -- Quitar el posible tag (edited o implemented) del final
    return name:gsub("%s*%[" .. project.t("edited") .. "%]$", ""):gsub("%s*%[" .. project.t("implemented") .. "%]$", ""):gsub("%s*$", "")
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
        group_name = M.clean_group_name(group_name)
        if sections_enabled then
            local slug = slugify(group_name)
            local section_plan = current_section_dir .. slug .. "/plan.wyt.md"
            if vim.fn.filereadable(section_plan) == 0 then
                print(loc.t("goto_no_section_plan") .. ": " .. section_plan .. "\n" .. loc.t("implementing") .. "'" .. group_name .. "'...\n")
                project.implement_group(current_plan_content, group_name, current_section_dir, sections_enabled)
            else
                if M.is_group_tagged(current_plan_content, group_name, "edited") then
                    prompt_reimplement_group(current_plan_content, group_name, current_section_dir, sections_enabled, section_plan)
                    return
                end
            end
            vim.cmd("tabnew " .. section_plan)
        else
            local text_path = current_section_dir .. "/text.wyt.md"
            if vim.fn.filereadable(text_path) == 0 then
                print(loc.t("goto_no_section_text") .. ": " .. text_path .. "\n" .. loc.t("implementing") .. "'" .. group_name .. "'...\n")
                project.implement_group(current_plan_content, group_name, current_section_dir, sections_enabled)
            else
                if M.is_group_tagged(current_plan_content, group_name, "edited") then
                    prompt_reimplement_group(current_plan_content, group_name, current_section_dir, sections_enabled, text_path)
                    return
                end
            end
            vim.cmd("tabnew " .. text_path)
            -- Opcional: buscar el grupo o idea en el texto y mover el cursor
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
        col = api.nvim_win_get_cursor(0)[2] + 1 -- Lua 1-based indexing
        group_name = get_group_tag_at_cursor(line, col)
        if group_name then
            goto_group_name()
            return
        end
        -- Si no hay grupo y no hay secciones, navega al texto
        if not sections_enabled then
            local text_path = current_section_dir .. "text.wyt.md"
            if vim.fn.filereadable(text_path) == 1 then
                print("Goto idea: " .. line:sub(3) .. "\n")
                vim.cmd("tabnew " .. text_path)
                -- Opcional: buscar la idea en el texto
            else
                print(loc.t("goto_no_section_text") .. ": " .. text_path)
            end
        end
        return
    end
end

function M.add_item_to_section(content, section, item)
    -- Eliminar cualquier \n del item
    item = item:gsub("\n", " ")
    local section_header = "## " .. project.t(section)
    local section_start = content:find(section_header)
    if section_start then
        local next_section = content:find("\n## ", section_start + #section_header)
        local section_end = next_section and (next_section - 1) or #content
        local before = content:sub(1, section_end)
        local after = content:sub(section_end + 1)
        -- Busca el último ítem en la sección
        local last_item_pos = 0
        for pos in before:gmatch("()\n%- [^\n]*") do
            last_item_pos = pos
        end
        if last_item_pos > 0 then
            -- Encuentra el final de la última línea de ítem
            local last_item_end = 0
            for pos in before:gmatch("()\n%- [^\n]*") do
                last_item_end = pos
            end
            -- Busca el salto de línea después del último ítem
            local next_newline = before:find("\n", last_item_end + 1) or (#before + 1)
            local before_items = before:sub(1, next_newline - 1)
            local after_items = before:sub(next_newline)
            return before_items .. "\n- " .. item .. after_items .. after
        else
            -- Si no hay ítems, agrega al final de la sección
            return before .. "\n- " .. item .. after
        end
    else
        return content .. "\n\n" .. section_header .. "\n- " .. item
    end
end

return M