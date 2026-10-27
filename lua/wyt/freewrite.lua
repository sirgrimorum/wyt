-- Free writing: a bare file in the project's `freewrite/` folder, written before
-- anything is planned. It is not a section, so the export, `:WYTNav` and
-- `:WYTSearch` never walk into it; it is committed on save like the rest, so
-- nothing typed in it is lost.
local M = {}

local uv = vim.uv or vim.loop

--- True when `path` is a file in the `freewrite/` folder of a WYT project root.
--- Any folder on disk may be called that, so the parent has to be a project.
--- A group named "Freewrite" slugs to the same folder; its WYT files are a
--- section's, not free writing.
function M.is_freewrite(path)
    if (path or ""):match("%.wyt%.md$") then return false end
    local root = (path or ""):match("^(.*[\\/])freewrite[\\/][^\\/]+%.md$")
    return root ~= nil and uv.fs_stat(root .. "config.wyt.yml") ~= nil
        and uv.fs_stat(root .. "plan.wyt.md") ~= nil
end

--- True when the file holds no more than `open` wrote: the prompt, or nothing.
function M.is_untouched(path)
    local f = io.open(path, "rb")
    if not f then return false end
    local content = f:read("*a")
    f:close()
    return vim.trim((content:gsub("^> [^\n]*", ""))) == ""
end

--- Open a new freewrite file, headed by `prompt` when there is one, in insert
--- mode at its end: the point is to start typing, not to look around.
function M.open(prompt)
    local project = require("wyt.project")
    local dir = project.project_root .. "freewrite/"
    vim.fn.mkdir(dir, "p")
    -- Named by the minute it was started, so the folder reads as a diary.
    -- A second start inside the same minute reopens the same file.
    local path = dir .. os.date("%Y-%m-%d-%H%M") .. ".md"
    if not uv.fs_stat(path) then
        -- A quote, not a heading: a `#` is structure everywhere else in WYT.
        -- Three newlines, not two: the last
        -- one loads as no line at all, and with two the writer typed straight
        -- into the blank line meant to separate the prompt from the text.
        project.write_file(path, prompt and ("> " .. prompt .. "\n\n\n") or "")
    end
    require("wyt.ui").edit_file(path)
    -- Reopened within its minute: start a new paragraph, or the new text is
    -- typed onto the end of the last one.
    local last = vim.api.nvim_buf_get_lines(0, -2, -1, false)[1]
    if last and last ~= "" then vim.api.nvim_buf_set_lines(0, -1, -1, false, { "", "" }) end
    vim.cmd("normal! G")
    vim.cmd("startinsert!")
end

--- Strip the screen down to the text. Set with `setlocal`, so the writer's
--- other windows keep their numbers and columns.
function M.setup_buf()
    local o = vim.opt_local
    o.wrap = true
    o.linebreak = true
    o.number = false
    o.relativenumber = false
    o.signcolumn = "no"
    o.cursorline = false
    o.colorcolumn = ""
    o.foldcolumn = "0"
end

return M
