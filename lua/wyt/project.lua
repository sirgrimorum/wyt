local uv = vim.uv or vim.loop  -- O2: vim.loop is deprecated in Neovim 0.10+
local api = vim.api
local loc = require("wyt.localization")
local M = {}

-- O10: per-buffer root cache; avoids re-walking the directory tree on every command
local _root_cache = {}

local function find_project_root_from_buffer()
    local buf_path = api.nvim_buf_get_name(0)
    if buf_path == "" then return vim.fn.getcwd() end
    if _root_cache[buf_path] then return _root_cache[buf_path] end  -- O10: cache hit

    local sep = package.config:sub(1,1)
    local dir = buf_path:match("^(.*"..sep..")")
    local last_valid = nil
    while dir and dir ~= "" do
        -- O4: vim.uv.fs_stat is faster than vim.fn.filereadable (no Vimscript call)
        if uv.fs_stat(dir .. "config.wyt.yml") and uv.fs_stat(dir .. "plan.wyt.md") then
            last_valid = dir
        else
            if last_valid then break end
        end
        dir = dir:match("^(.*"..sep..")[^"..sep.."]+"..sep.."$")
    end
    local result = last_valid or vim.fn.getcwd()
    _root_cache[buf_path] = result  -- O10: populate cache
    return result
end

M.project_root = ""
M.config_path = ""
M.plan_path = ""
M.current_section_dir = ""
M.section_config_path = ""
M.section_plan_path = ""
M.lang = "en"

-- Exported so other modules (group.lua) can slugify consistently
function M.slugify(str)
    return str:lower():gsub("%s+", "-"):gsub("[^%w%-]", "")
end

local slugify = M.slugify  -- local alias for internal use

function M.read_file(path)
    local fd = uv.fs_open(path, "r", 438)
    if not fd then return nil end
    local stat = uv.fs_fstat(fd)
    local data = uv.fs_read(fd, stat.size, 0)
    uv.fs_close(fd)
    return data
end

function M.write_file(path, content)
    -- F7: removed assert() which crashed on unwritable paths
    local fd = uv.fs_open(path, "w", 438)
    if not fd then
        vim.notify("[WYT] Cannot write to: " .. path, vim.log.levels.ERROR)
        return false
    end
    uv.fs_write(fd, content, -1)
    uv.fs_close(fd)
    return true
end

local function get_project_lang()
    local config_content = M.read_file(M.config_path)
    if not config_content then return "en" end
    local lang = config_content:match("lang:%s*(%w+)")
    return lang or "en"
end

function M.get_section_dir()
    local plan_path = api.nvim_buf_get_name(0)
    return plan_path:match("^(.*[\\/])") or vim.fn.getcwd() .. "/"
end

-- F11: was missing `local` — leaked as globals
local function set_root_data()
    -- F2/O10: always re-detect from current buffer (uses per-buffer cache internally)
    -- removed early return that caused stale root when switching projects
    M.project_root = find_project_root_from_buffer()
    local config_path = M.project_root .. "config.wyt.yml"
    local plan_path = M.project_root .. "plan.wyt.md"
    -- O4: vim.uv.fs_stat instead of vim.fn.filereadable
    if uv.fs_stat(config_path) and uv.fs_stat(plan_path) then
        M.config_path = config_path
        M.plan_path = plan_path
        M.lang = get_project_lang()
        return true
    end
    return false
end

-- F11: was missing `local`
local function set_section_data()
    local buf_path = api.nvim_buf_get_name(0)
    M.current_section_dir = buf_path:match("^(.*[\\/])") or vim.fn.getcwd() .. "/"
    -- O4: fs_stat; F1: fallback to M.config_path/M.plan_path (were undefined `config_path`/`plan_path`)
    if uv.fs_stat(M.current_section_dir .. "config.wyt.yml") then
        M.section_config_path = M.current_section_dir .. "config.wyt.yml"
    else
        M.section_config_path = M.config_path
    end
    if uv.fs_stat(M.current_section_dir .. "plan.wyt.md") then
        M.section_plan_path = M.current_section_dir .. "plan.wyt.md"
    else
        M.section_plan_path = M.plan_path
    end
end

function M.setup()
    local project_found = set_root_data()
    if not project_found then
        -- O6: vim.notify instead of print
        vim.notify(loc.t("no_project"), vim.log.levels.WARN)
        return false
    end
    set_section_data()
    return true
end

function M.t(key)
    return loc.t(key, M.lang)
end

function M.get_project_type()
    local config_content = M.read_file(M.config_path)
    if not config_content then return "essay" end
    return config_content:match("type:%s*(%w+)") or "essay"
end

local function mkdir(path)
    local sep = package.config:sub(1,1)
    local parts = {}
    path = path:gsub("[/\\]", sep)
    local root = ""
    if path:match("^%a:"..sep) then
        root = path:sub(1,3)
        path = path:sub(4)
    elseif path:sub(1,1) == sep then
        root = sep
        path = path:sub(2)
    end
    for part in string.gmatch(path, "[^"..sep.."]+") do
        table.insert(parts, part)
    end
    local current = root
    for _, part in ipairs(parts) do
        current = current == "" and part or (current .. sep .. part)
        uv.fs_mkdir(current, 493)
    end
end

local function run_git_init(path)
    vim.fn.system({'git', '-C', path, 'init'})
    vim.fn.system({'git', '-C', path, 'add', '.'})
    vim.fn.system({'git', '-C', path, 'commit', '-m', 'Initial commit'})
end

function M.commit_changes(msg)
    vim.fn.system({'git', '-C', M.project_root, 'add', '.'})
    vim.fn.system({'git', '-C', M.project_root, 'commit', '-m', msg})
end

function M.new_project()
    local opts = {}

    vim.ui.select({"en", "es"}, {prompt = loc.t("choose_lang")}, function(lang)
        opts.lang = lang or "en"
        vim.ui.select({"novel", "short_story", "essay", "summary"}, {prompt = loc.t("choose_type")}, function(type)
            opts.type = type or "novel"
            vim.ui.input({prompt = loc.t("choose_path")}, function(base_path)
                opts.base_path = base_path or vim.fn.getcwd()
                vim.ui.input({prompt = loc.t("choose_name")}, function(name)
                    opts.name = name or "my_project"
                    opts.slug = slugify(opts.name)
                    vim.ui.select({loc.t("content"), loc.t("definition")}, {prompt = loc.t("choose_content_type")}, function(content_type)
                        opts.content_type = content_type == loc.t("content") and "content" or "definition"
                        vim.ui.select({loc.t("yes"), loc.t("no")}, {prompt = loc.t("has_sections")}, function(has_sections)
                            opts.sections = has_sections == loc.t("yes")
                            vim.ui.select({loc.t("same_window"), loc.t("new_window")}, {prompt = loc.t("open_where")}, function(open_where)
                                local root = opts.base_path .. "/" .. opts.slug
                                mkdir(root)
                                M.write_file(root .. "/config.wyt.yml", string.format(
                                    "lang: %s\ntype: %s\ncontent_type: %s\nsections: %s\nname: %s\n",
                                    opts.lang, opts.type, opts.content_type, tostring(opts.sections), opts.name
                                ))
                                M.write_file(root .. "/plan.wyt.md", "# " .. opts.name .. "\n\n" .. loc.t("plan_intro"))
                                M.write_file(root .. "/export.wyt.md", "# " .. opts.name .. " " .. loc.t("export_intro"))
                                run_git_init(root)
                                local file_to_open = root .. "/plan.wyt.md"
                                -- F5: fnameescape prevents path injection for names with spaces/special chars
                                if open_where == loc.t("new_window") then
                                    vim.cmd("tabnew " .. vim.fn.fnameescape(file_to_open))
                                else
                                    vim.cmd("edit " .. vim.fn.fnameescape(file_to_open))
                                end
                                -- O6: vim.notify instead of print
                                vim.notify(loc.t("project_created") .. root, vim.log.levels.INFO)
                            end)
                        end)
                    end)
                end)
            end)
        end)
    end)
end


function M.get_ideas(plan_content, section_header)
    local ideas = {}
    local start = plan_content:find(section_header)
    if not start then return ideas end
    local next_section = plan_content:find("\n## ", start + #section_header) or #plan_content + 1
    local ideas_block = next_section and plan_content:sub(start + #section_header, next_section - 1) or plan_content:sub(start + #section_header)
    for idea in ideas_block:gmatch("%- ([^\n]+)") do
        local clean_idea = idea:gsub("%s*%[" .. M.t("group_tag") .. ": [^%]]+%]", "")
        table.insert(ideas, clean_idea)
    end
    return ideas
end

function M.mark_group_status(content, group_name, status)
    if not content then
        return content
    end
    local group_pat = "## " .. M.t("group_tag") .. ": " .. group_name
    local status_tag = "[" .. M.t(status) .. "]"
    local new_content
    if content:find(group_pat .. " %[") then
        new_content = content:gsub(group_pat .. " %[.-%]", group_pat .. " " .. status_tag)
    else
        new_content = content:gsub(group_pat, group_pat .. " " .. status_tag)
    end
    return new_content
end

local function update_changes_in_buffer(path, content)
    M.write_file(path, content)
    local buf_path = vim.api.nvim_buf_get_name(0)
    if buf_path == (path) then
        vim.cmd("e! " .. vim.fn.fnameescape(path))  -- F5: fnameescape
    end
end


function M.clean_group_name(name)
    return name:gsub("%s*%[" .. M.t("edited") .. "%]$", ""):gsub("%s*%[" .. M.t("implemented") .. "%]$", ""):gsub("%s*$", "")
end

function M.get_groups(plan_content)
    local groups = {}
    local group_header = "## " .. M.t("group_tag") .. ": "
    for group in plan_content:gmatch(group_header .. "([^\n]+)") do
        local clean_group = M.clean_group_name(group)
        table.insert(groups, clean_group)
    end
    return groups
end

function M.implement_group(current_plan_content, group_name, section_dir, sections_enabled)
    local current_section_dir = M.get_section_dir()
    local ideas = M.get_ideas(current_plan_content, "## " .. M.t("group_tag") .. ": " .. group_name)
    if sections_enabled then
        local slug = slugify(group_name)
        local group_section_dir = section_dir .. slug .. "/"
        mkdir(group_section_dir)
        local plan_path = group_section_dir .. "plan.wyt.md"
        -- O4: fs_stat instead of vim.fn.filereadable
        if uv.fs_stat(plan_path) then
            if uv.fs_stat(group_section_dir .. "plan.old.wyt.md") then
                vim.fn.delete(group_section_dir .. "plan.old.wyt.md")
            end
            vim.fn.rename(plan_path, group_section_dir .. "plan.old.wyt.md")
        end
        if not uv.fs_stat(plan_path) then
            local plan_content = "# " .. group_name .. "\n\n## " .. M.t("ideas_section") .. "\n"
            for _, idea in ipairs(ideas) do
                plan_content = plan_content .. "\n\n## " .. M.t("group_tag") .. ": " .. idea .. "\n"
            end
            M.write_file(plan_path, plan_content)
        end
        local config_path = group_section_dir .. "config.wyt.yml"
        if not uv.fs_stat(config_path) then
            M.write_file(config_path, "type: content\nsections: false\n")
        end
        current_plan_content = M.mark_group_status(current_plan_content, group_name, "implemented")
        update_changes_in_buffer(current_section_dir .. "plan.wyt.md", current_plan_content)
    else
        local text_path = section_dir .. "text.wyt.md"
        -- O4: fs_stat instead of vim.fn.filereadable
        local text_content = uv.fs_stat(text_path) and M.read_file(text_path) or ""
        local group_order = M.get_groups(current_plan_content)
        local blocks = {}
        local previous_content = ""
        local next_content = ""
        local pattern = "()\n*## " .. M.t("group_tag") .. ": ([^\n%[]+)%s*%[?[^%]\n]*%]?\n"
        local last_end = 1
        local group_blocks = {}
        local first_start = 0
        for s, gname in text_content:gmatch(pattern) do
            if first_start == 0 then
                first_start = s
            end
            if s > last_end then
                next_content = next_content .. text_content:sub(last_end, s - 1)
            end
            local e = text_content:find("\n## ", s + 2)
            local block
            if e and e > s + 2 then
                block = text_content:sub(s, e - 1)
            else
                block = text_content:sub(s)
                e = #text_content + 1
            end
            group_blocks[M.clean_group_name(gname)] = block
            last_end = e
        end
        if first_start > 0 then
            previous_content = text_content:sub(1, first_start - 1)
            next_content = last_end <= #text_content and text_content:sub(last_end) or ""
        else
            previous_content = text_content
        end
        local new_block = "\n\n## " .. M.t("group_tag") .. ": " .. group_name .. "\n"
        for _, idea in ipairs(ideas) do
            new_block = new_block .. "\n\n*" .. M.t("create_paragraph") .. "[" .. idea .. "]*\n"
        end
        local new_text = previous_content
        for _, gname in ipairs(group_order) do
            if gname == group_name then
                new_text = new_text .. new_block
            elseif group_blocks[gname] then
                new_text = new_text .. group_blocks[gname]
                group_blocks[gname] = nil
            end
        end
        for gname, block in pairs(group_blocks) do
            new_text = new_text .. "```old\n" .. block .. "\n```"
        end
        new_text = new_text .. next_content
        M.write_file(text_path, new_text)
        current_plan_content = M.mark_group_status(current_plan_content, group_name, "implemented")
        update_changes_in_buffer(current_section_dir .. "plan.wyt.md", current_plan_content)
    end
    M.commit_changes("Implement group: " .. group_name)
end

return M
