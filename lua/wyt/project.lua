local uv = vim.uv or vim.loop  -- O2: vim.loop is deprecated in Neovim 0.10+
local api = vim.api
local loc = require("wyt.localization")
local ui = require("wyt.ui")
local types = require("wyt.types")
local M = {}

-- O10: per-buffer root cache; avoids re-walking the directory tree on every command
local _root_cache = {}

-- F13: every path this module builds is `dir .. "config.wyt.yml"`, so a root
-- without its trailing separator silently produces "D:\WYTconfig.wyt.yml".
local function ensure_trailing_sep(path)
    if path:match("[\\/]$") then return path end
    return path .. "/"
end

local function find_project_root_from_buffer()
    local buf_path = api.nvim_buf_get_name(0)
    local cwd = ensure_trailing_sep(vim.fn.getcwd())
    if buf_path == "" then return cwd end
    if _root_cache[buf_path] then return _root_cache[buf_path] end  -- O10: cache hit

    -- F13: match either separator. On Windows package.config reports "\" while
    -- the buffer name commonly uses "/", which made every walk-up fail and fall
    -- back to the cwd — the "no project found" report from :WYTNav/:WYTSearch.
    local dir = buf_path:match("^(.*[\\/])")
    local last_valid = nil
    while dir and dir ~= "" do
        -- O4: vim.uv.fs_stat is faster than vim.fn.filereadable (no Vimscript call)
        if uv.fs_stat(dir .. "config.wyt.yml") and uv.fs_stat(dir .. "plan.wyt.md") then
            last_valid = dir
        elseif last_valid then
            break
        end
        local parent = dir:match("^(.*[\\/])[^\\/]+[\\/]$")
        if parent == dir then break end  -- defensive: never spin on a fixed point
        dir = parent
    end
    -- O10: cache confirmed roots only; caching the cwd fallback would pin a
    -- failed lookup for the lifetime of the buffer.
    if last_valid then _root_cache[buf_path] = last_valid end
    return last_valid or cwd
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
    -- `%w` excludes `_`, so this used to read `short_story` as `short` and fall
    -- back to essay for every type whose name has an underscore. The frontier
    -- keeps the key itself from matching the tail of `content_type:`.
    return config_content:match("%f[%w_]type:%s*([%w_]+)") or "essay"
end

--- The frame every generation is given: the literary type, plus the plan's
--- Description section when it has one. Kept short, since it is prepended to
--- every prompt. The type goes in under its name in the writer's language, not
--- as the id: `long_novel` inside a Spanish prompt is noise the model has to
--- decode before it can use it.
function M.description_context(plan_content)
    local ctx = types.label(M.get_project_type(), M.lang)
    local header = "## " .. M.t("description_section")
    local start = (plan_content or ""):find(header, 1, true)
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

--- Level of `dir` in the section tree: the project root is level 1, a section
--- created inside it level 2, and so on. Compared against the type's
--- `section_depth` to decide whether a new section may hold sub-sections.
function M.section_level(dir)
    local root = M.project_root
    if not root or root == "" then return 1 end
    -- F13 again: the two paths can disagree on the separator, so normalise
    -- before measuring one against the other.
    local norm = function(p) return (p:gsub("\\", "/")) end
    local rel = norm(dir):sub(#norm(root) + 1)
    local level = 1
    for _ in rel:gmatch("[^/]+") do level = level + 1 end
    return level
end

--- True when `section_dir` holds definitions rather than text of its own:
--- reference material the writer searches, kept out of the export.
function M.is_definition_section(section_dir)
    local cfg = M.read_file(section_dir .. "config.wyt.yml") or ""
    return cfg:match("content_type:%s*definition") ~= nil
end

-- `prose` is the absence of an archetype, so it reads back as nil: the section
-- is guided by the project type alone.
local function kind_in(config_content)
    local kind = (config_content or ""):match("section_kind:%s*([%w_]+)")
    if not kind or kind == "prose" then return nil end
    return kind
end

--- The archetype the current section was created with (`characters`,
--- `chronology`, ...), or nil for a plain prose section.
function M.get_section_kind()
    return kind_in(M.read_file(M.section_config_path or ""))
end

--- The same, for any section directory.
function M.section_kind_of(dir)
    return kind_in(M.read_file(dir .. "config.wyt.yml"))
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

-- Absolute, separator-normalised path with no trailing slash.
-- Empty input means "the current working directory"; `~`, `$VARS` and relative
-- paths (`.`, `../foo`) are all expanded.
local function normalize_path(p)
    p = vim.trim(p or "")
    if p == "" then p = vim.fn.getcwd() end
    p = vim.fn.expand(p)
    p = vim.fn.fnamemodify(p, ":p")
    p = p:gsub("[\\/]+$", "")
    return (p:gsub("\\", "/"))
end

function M.new_project()
    local opts = {}
    -- F12: every prompt after the language step must speak the chosen language,
    -- so the wizard uses its own `t` instead of the module-wide loc.t default.
    local t = function(key) return loc.t(key, opts.lang or loc.get_lang()) end
    local p = function(key) return loc.pad(t(key)) end
    local cancelled = function()
        vim.notify(t("wizard_cancelled"), vim.log.levels.INFO)
    end

    vim.ui.select({"en", "es"}, {prompt = loc.t("choose_lang")}, function(lang)
        if not lang then return cancelled() end
        opts.lang = lang
        -- The ids are what the config stores, but nobody picks a text type from
        -- `long_novel`: the list shows each type's name and what it does to the
        -- finished text, in the language chosen a question ago.
        local type_opts = {
            prompt = t("choose_type"),
            format_item = function(id) return types.menu_label(id, lang) end,
        }
        vim.ui.select(types.names(), type_opts, function(type)
            if not type then return cancelled() end
            opts.type = type
            vim.ui.input({prompt = p("choose_path"), default = vim.fn.getcwd()}, function(base_path)
                if not base_path then return cancelled() end
                opts.base_path = normalize_path(base_path)
                vim.ui.input({prompt = p("choose_name")}, function(name)
                    if not name or vim.trim(name) == "" then return cancelled() end
                    opts.name = vim.trim(name)
                    vim.ui.input({prompt = p("choose_folder"), default = slugify(opts.name)}, function(folder)
                        if not folder then return cancelled() end
                        folder = vim.trim(folder)
                        -- "." (or an empty answer) keeps the base path as the project root
                        opts.slug = (folder == "" or folder == "." or folder == "./") and "" or slugify(folder)
                        local root = opts.slug == "" and opts.base_path
                            or (opts.base_path .. "/" .. opts.slug)
                        if uv.fs_stat(root .. "/config.wyt.yml") then
                            vim.notify(t("project_exists") .. root, vim.log.levels.ERROR)
                            return
                        end
                        vim.ui.select({t("content"), t("definition")}, {prompt = t("choose_content_type")}, function(content_type)
                            if not content_type then return cancelled() end
                            opts.content_type = content_type == t("content") and "content" or "definition"
                            local function ask_where_to_open()
                                vim.ui.select({t("same_window"), t("new_window")}, {prompt = t("open_where")}, function(open_where)
                                    if not open_where then return cancelled() end
                                    mkdir(root)
                                    M.write_file(root .. "/config.wyt.yml", string.format(
                                        "lang: %s\ntype: %s\ncontent_type: %s\nsections: %s\nname: %s\n",
                                        opts.lang, opts.type, opts.content_type, tostring(opts.sections), opts.name
                                    ))
                                    local plan_template = string.format(
                                        "# %s\n\n## %s\n\n## %s\n\n## %s\n",
                                        opts.name,
                                        loc.t("description_section", opts.lang),
                                        loc.t("ideas_section", opts.lang),
                                        loc.t("groups_section", opts.lang)
                                    )
                                    M.write_file(root .. "/plan.wyt.md", plan_template)
                                    M.write_file(root .. "/export.wyt.md", "")
                                    run_git_init(root)
                                    -- the rest of the session now speaks the project language
                                    loc.set_lang(opts.lang)
                                    local file_to_open = root .. "/plan.wyt.md"
                                    -- F5: fnameescape prevents path injection for names with spaces/special chars
                                    if open_where == t("new_window") then
                                        vim.cmd("tabnew " .. vim.fn.fnameescape(file_to_open))
                                    else
                                        vim.cmd("edit " .. vim.fn.fnameescape(file_to_open))
                                    end
                                    -- O6: vim.notify instead of print
                                    vim.notify(t("project_created") .. root, vim.log.levels.INFO)
                                end)
                            end

                            -- Only types that allow more than one plan level can
                            -- have sub-sections, so the others are not asked a
                            -- question with one possible answer.
                            if types.section_depth(opts.type) > 1 then
                                vim.ui.select({t("yes"), t("no")}, {prompt = t("has_sections")}, function(has_sections)
                                    if not has_sections then return cancelled() end
                                    opts.sections = has_sections == t("yes")
                                    ask_where_to_open()
                                end)
                            else
                                opts.sections = false
                                ask_where_to_open()
                            end
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

--- Turn a group into a section, or into text when the section holds no
--- sub-sections. `on_done` runs once the files are on disk; a new section asks
--- the writer what it holds first, so it never runs if they cancel.
function M.implement_group(current_plan_content, group_name, section_dir, sections_enabled, on_done)
    local current_section_dir = M.get_section_dir()
    local ideas = M.get_ideas(current_plan_content, "## " .. M.t("group_tag") .. ": " .. group_name)
    if sections_enabled then
        local slug = slugify(group_name)
        local group_section_dir = section_dir .. slug .. "/"
        local config_path = group_section_dir .. "config.wyt.yml"

        -- `kind` is nil when the section already has a config: an existing
        -- section keeps the archetype it was created with.
        local function build(kind)
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
            if kind then
                -- `type` is the literary type, inherited from the project, not
                -- the content type: a section of an essay is still an essay.
                -- Whether this one may hold sub-sections is the type's business:
                -- a long novel nests parts inside books, a summary nests nothing.
                -- The archetype is what decides the content type, and what the
                -- section's own questions will be from here on.
                --
                -- The type's depth is only the default written here at creation.
                -- Hand-editing this file's `sections:` to true afterwards is the
                -- real override, and it applies to this branch alone.
                local project_type = M.get_project_type()
                local nests = M.section_level(group_section_dir) < types.section_depth(project_type)
                M.write_file(config_path, string.format(
                    "type: %s\nsection_kind: %s\ncontent_type: %s\nsections: %s\n",
                    project_type, kind.id, kind.content_type, tostring(nests)))
            end
            current_plan_content = M.mark_group_status(current_plan_content, group_name, "implemented")
            update_changes_in_buffer(current_section_dir .. "plan.wyt.md", current_plan_content)
            M.commit_changes("Implement group: " .. group_name)
            if on_done then on_done() end
        end

        if uv.fs_stat(config_path) then
            build(nil)
        elseif M.is_definition_section(section_dir) then
            -- Inside reference material the question is already answered: a
            -- section of a Characters section is still about characters. Asking
            -- again could make a child that is content inside a parent the
            -- export skips, which would be neither exported nor searchable.
            build({ id = M.section_kind_of(section_dir) or "prose", content_type = "definition" })
        else
            -- A section carries the text itself, or it works out something the
            -- text needs: who the people are, when things happen, what turns.
            -- The answer decides the section's questions, and whether it reaches
            -- the export or stays reference material, so it is asked before
            -- anything is written.
            local available = types.section_kinds(M.get_project_type())
            local labels, by_label = {}, {}
            for _, kind in ipairs(available) do
                local label = kind.label[M.lang] or kind.label.en
                labels[#labels + 1] = label
                by_label[label] = kind
            end
            ui.ask_select({
                title = M.t("section_type"),
                question = M.t("choose_section_kind") .. " '" .. group_name .. "'",
            }, labels, function(choice)
                if not choice or not by_label[choice] then return end
                build(by_label[choice])
            end)
        end
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
        if types.multi_idea_paragraph(M.get_project_type()) and #ideas > 0 then
            -- A summary condenses: the whole group becomes one paragraph, so it
            -- gets one placeholder holding every idea the writer has to fold in.
            new_block = new_block .. "\n\n*" .. M.t("create_paragraph")
                .. "[" .. table.concat(ideas, "; ") .. "]*\n"
        else
            for _, idea in ipairs(ideas) do
                new_block = new_block .. "\n\n*" .. M.t("create_paragraph") .. "[" .. idea .. "]*\n"
            end
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
        M.commit_changes("Implement group: " .. group_name)
        if on_done then on_done() end
    end
end

return M
