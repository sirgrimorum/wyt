local uv = vim.loop
local loc = require("wyt.localization")
local M = {}

local function slugify(str)
    return str:lower():gsub("%s+", "-"):gsub("[^%w%-]", "")
end

local function write_file(path, content)
    local fd = assert(uv.fs_open(path, "w", 438))
    uv.fs_write(fd, content, -1)
    uv.fs_close(fd)
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
    vim.fn.system({'git', 'init'}, path)
    vim.fn.system({'git', 'add', '.'}, path)
    vim.fn.system({'git', 'commit', '-m', 'Initial commit'}, path)
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
                                write_file(root .. "/config.wyt.yml", string.format(
                                    "lang: %s\ntype: %s\ncontent_type: %s\nsections: %s\nname: %s\n",
                                    opts.lang, opts.type, opts.content_type, tostring(opts.sections), opts.name
                                ))
                                write_file(root .. "/plan.wyt.md", "# " .. opts.name .. "\n\n" .. loc.t("plan_intro"))
                                write_file(root .. "/export.wyt.md", "# " .. opts.name .. " " .. loc.t("export_intro"))
                                if opts.sections then
                                    mkdir(root .. "/sections")
                                else
                                    write_file(root .. "/text.wyt.md", "# " .. opts.name .. " " .. loc.t("text_intro"))
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