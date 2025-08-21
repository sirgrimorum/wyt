local uv = vim.loop
local loc = require("wyt.localization")
local M = {}

local function find_project_root_from_buffer()
    local buf_path = vim.api.nvim_buf_get_name(0)
    if buf_path == "" then return vim.fn.getcwd() end
    local sep = package.config:sub(1,1)
    local dir = buf_path:match("^(.*"..sep..")")
    local last_valid = nil
    while dir and dir ~= "" do
        local config_path = dir .. "config.wyt.yml"
        local plan_path = dir .. "plan.wyt.md"
        if vim.fn.filereadable(config_path) == 1 and vim.fn.filereadable(plan_path) == 1 then
            last_valid = dir
        else
            if last_valid then
                return last_valid
            end
        end
        dir = dir:match("^(.*"..sep..")[^"..sep.."]+"..sep.."$")
    end
    return last_valid or vim.fn.getcwd()
end

M.project_root = ""
M.config_path = ""
M.plan_path = ""
M.lang = "en"

local function slugify(str)
    return str:lower():gsub("%s+", "-"):gsub("[^%w%-]", "")
end

function M.read_file(path)
    local fd = uv.fs_open(path, "r", 438)
    if not fd then return nil end
    local stat = uv.fs_fstat(fd)
    local data = uv.fs_read(fd, stat.size, 0)
    uv.fs_close(fd)
    return data
end

function M.write_file(path, content)
    local fd = assert(uv.fs_open(path, "w", 438))
    uv.fs_write(fd, content, -1)
    uv.fs_close(fd)
end

local function get_project_lang()
    local config_content = M.read_file(M.config_path)
    if not config_content then return "en" end
    local lang = config_content:match("lang:%s*(%w+)")
    return lang or "en"
end

function M.setup()
    if M.project_root ~= "" and M.config_path ~= "" and M.plan_path ~= "" then
        return true
    end
    M.project_root = find_project_root_from_buffer()
    local config_path = M.project_root .. "config.wyt.yml"
    local plan_path = M.project_root .. "plan.wyt.md"
    if vim.fn.filereadable(config_path) == 1 and vim.fn.filereadable(plan_path) == 1 then
        M.config_path = config_path
        M.plan_path = plan_path
        M.lang = get_project_lang()
        return true
    else
        print(loc.t("no_project"))
        print(" [WYT] Project root: " .. M.project_root)
        return false
    end
end

local function mkdir(path)
    local sep = package.config:sub(1,1)
    local parts = {}
    -- Normaliza los separadores
    path = path:gsub("[/\\]", sep)
    -- Si la ruta es absoluta, conserva la raíz (ej: "d:\")
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
                                -- Crear estructura
                                local root = opts.base_path .. "/" .. opts.slug
                                mkdir(root)
                                M.write_file(root .. "/config.wyt.yml", string.format(
                                    "lang: %s\ntype: %s\ncontent_type: %s\nsections: %s\nname: %s\n",
                                    opts.lang, opts.type, opts.content_type, tostring(opts.sections), opts.name
                                ))
                                M.write_file(root .. "/plan.wyt.md", "# " .. opts.name .. "\n\n" .. loc.t("plan_intro"))
                                M.write_file(root .. "/export.wyt.md", "# " .. opts.name .. " " .. loc.t("export_intro"))
                                if opts.sections then
                                    mkdir(root .. "/sections")
                                else
                                    M.write_file(root .. "/text.wyt.md", "# " .. opts.name .. " " .. loc.t("text_intro"))
                                end
                                -- Inicializar git
                                run_git_init(root)
                                -- Abrir archivo principal
                                local file_to_open = root .. "/plan.wyt.md"
                                if open_where == loc.t("new_window") then
                                    vim.cmd("tabnew " .. file_to_open)
                                else
                                    vim.cmd("edit " .. file_to_open)
                                end
                                print(loc.t("project_created") .. root)
                            end)
                        end)
                    end)
                end)
            end)
        end)
    end)
end

return M