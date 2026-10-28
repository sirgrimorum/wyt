-- :WYTOutline, the project as the export walks it, in a sidebar: each section
-- and its groups, with what is still open in each. :WYTNav is a picker, gone
-- once used; finding the way around a large project needs the map left in view.
-- It reads the disk only, never the model.
local M = {}

local WIDTH = 32
local state = { buf = nil, win = nil, root = nil, rows = {} }
local ns = vim.api.nvim_create_namespace("wyt_outline")
-- Set with scope "local": vim.wo[win] has :set semantics and leaked nonumber
-- and nowrap into every window opened after the sidebar. winfixbuf keeps a
-- jump or :e from loading a file into the 32 columns.
local WIN_OPTS = {
    number = false, relativenumber = false, signcolumn = "no", foldcolumn = "0", wrap = false,
    spell = false, list = false, cursorline = true, winfixwidth = true, winfixbuf = true,
}

local function line_of_group(lines, marker, project_mod, name)
    for i, line in ipairs(lines) do
        local g = line:match(marker)
        if g and project_mod.clean_group_name(g) == name then return i end
    end
end

--- The outline of the project, in plan order: rows { text, count, path, line,
--- plan, planned, freewrite }. A planned row is a group the plan names and
--- nothing has been written for. A group counts its placeholders and wyt
--- markers; a section counts everything open in it and under it, so the root
--- is the whole project and the numbers lead down to where the work is. Walked
--- here rather than from status.sections so a planned group sits where its plan
--- puts it, between the sections around it; the walk is the same, a folder no
--- plan names is not part of it.
function M.rows(project_mod)
    local status = require("wyt.status")
    local pat = require("wyt.text").placeholder_pattern(project_mod)
    local marker = status.group_marker(project_mod)
    local rows = {}
    local function walk(dir, level)
        local indent = ("  "):rep(level - 1)
        local plan_path, text_path = dir .. "plan.wyt.md", dir .. "text.wyt.md"
        local plan_content = project_mod.read_file(plan_path) or ""
        -- A level that holds sub-sections has no text the export reads: its
        -- groups are the folders under it, and it opens its plan.
        local nested = status.nested(project_mod, dir)
        local text = not nested and project_mod.read_file(text_path)
        local gaps = status.plan_gaps(project_mod, plan_content)
        local section = {
            text = indent .. (plan_content:match("^#%s+([^\r\n]+)") or vim.fn.fnamemodify(dir, ":h:t")),
            count = gaps.ungrouped,
            path = text and text_path or plan_path,
            plan = plan_path,
        }
        rows[#rows + 1] = section
        local written, order = {}, {}
        if text then
            local find = require("wyt.markers").find
            local lines = status.lines(text)
            local parked = status.parked(lines)
            local group
            for i, line in ipairs(lines) do
                if not parked[i] then
                    local name = line:match(marker)
                    if name then
                        name = project_mod.clean_group_name(name)
                        group = { text = indent .. "  " .. name, count = 0, path = text_path, line = i, plan = plan_path }
                        written[name], order[#order + 1] = group, name
                    else
                        local open = (line:match(pat) and 1 or 0) + #find(line)
                        section.count = section.count + open
                        if group then group.count = group.count + open end
                    end
                end
            end
        end
        local plan_lines
        for _, name in ipairs(project_mod.get_groups(plan_content)) do
            local sub = nested and project_mod.group_dir(dir, name)
            if sub then
                section.count = section.count + walk(sub, level + 1)
            elseif written[name] then
                rows[#rows + 1], written[name] = written[name], nil
            else
                plan_lines = plan_lines or status.lines(plan_content)
                section.count = section.count + 1
                rows[#rows + 1] = {
                    text = indent .. "  ○ " .. name, count = 0, planned = true,
                    path = plan_path, line = line_of_group(plan_lines, marker, project_mod, name), plan = plan_path,
                }
            end
        end
        -- A group the plan no longer names still holds prose the export prints.
        for _, name in ipairs(order) do
            if written[name] then rows[#rows + 1] = written[name] end
        end
        return section.count
    end
    walk(project_mod.project_root, 1)
    -- Writing not placed yet is part of the project too, and easy to forget.
    local files, dir = status.freewrites(project_mod)
    if #files > 0 then
        -- The row opens the newest before :WYTPlace runs: Place resolves its
        -- project from the buffer, and the main window may show another's.
        rows[#rows + 1] = { text = project_mod.t("outline_freewrite"), count = #files, freewrite = true, path = dir .. files[1] }
    end
    return rows
end

local function valid()
    return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

-- One sidebar, in the tab the writer is in: :WYTOutline in another tab moves
-- it there instead of closing the one they left behind.
local function here()
    return valid() and vim.api.nvim_win_get_tabpage(state.win) == vim.api.nvim_get_current_tabpage()
end

--- Redraw the outline from disk. A no-op when it is closed, or when the last
--- project WYT resolved is another one: a save there says nothing about this map.
function M.refresh()
    if not valid() then return end
    local project = require("wyt.project")
    local ui = require("wyt.ui")
    -- Canonical on both sides: the root from the cwd ends in "/" and the one
    -- from a buffer in "\", which silenced every refresh after the first save.
    if ui.canonical(project.project_root) ~= ui.canonical(state.root) then return end
    state.rows = M.rows(project)
    local width = vim.api.nvim_win_get_width(state.win) - 1
    local lines = {}
    for i, r in ipairs(state.rows) do
        local count = r.count > 0 and tostring(r.count) or ""
        local text = ui.truncate(r.text, width - #count - 1)
        lines[i] = text .. (" "):rep(width - vim.fn.strdisplaywidth(text) - #count) .. count
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = project.t("outline_keys")
    vim.bo[state.buf].modifiable = true
    vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
    vim.bo[state.buf].modifiable = false
    vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
    local function dim(i) vim.api.nvim_buf_set_extmark(state.buf, ns, i - 1, 0, { line_hl_group = "Comment" }) end
    for i, r in ipairs(state.rows) do
        if r.planned then dim(i) end
    end
    dim(#lines)
end

-- The window the writer was working in, or a new one when the outline is all
-- there is: opening a file in the sidebar itself would lose the map.
local function main_window()
    local prev = vim.fn.win_getid(vim.fn.winnr("#"))
    local wins = vim.tbl_filter(function(w)
        return w ~= state.win and vim.api.nvim_win_get_config(w).relative == ""
            and vim.bo[vim.api.nvim_win_get_buf(w)].buftype == ""
    end, vim.api.nvim_tabpage_list_wins(0))
    if vim.tbl_contains(wins, prev) then return vim.api.nvim_set_current_win(prev) end
    if wins[1] then return vim.api.nvim_set_current_win(wins[1]) end
    vim.cmd("botright vnew")
    -- Split from the sidebar, it copied the sidebar's options, winfixbuf too.
    for k in pairs(WIN_OPTS) do
        vim.api.nvim_set_option_value(k, vim.api.nvim_get_option_value(k, { scope = "global" }), { scope = "local", win = 0 })
    end
end

local function open_row(plan)
    local row = state.rows[vim.api.nvim_win_get_cursor(0)[1]]
    if not row then return end
    main_window()
    if row.freewrite then
        require("wyt.ui").edit_file(row.path)
        return require("wyt.place").open()
    end
    require("wyt.ui").edit_file(plan and row.plan or row.path)
    if row.line and (not plan or row.planned) then pcall(vim.api.nvim_win_set_cursor, 0, { row.line, 0 }) end
end

local function make_buf()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].filetype = "wytoutline"
    vim.bo[buf].modifiable = false
    local function map(lhs, fn) vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true }) end
    map("<CR>", function() open_row(false) end)
    map("p", function() open_row(true) end)
    map("q", M.toggle)
    -- Coming back to the map after writing elsewhere: what was open may be done.
    -- Also the first draw, since opening the window enters the buffer.
    vim.api.nvim_create_autocmd("BufEnter", { buffer = buf, callback = function() M.refresh() end })
    return buf
end

--- `:WYTOutline`: open the sidebar on the current project, or close it.
function M.toggle()
    if here() then
        -- The writing window takes the focus back, and a new one is made when
        -- the sidebar is the last: closing the last window is E444.
        main_window()
        return vim.api.nvim_win_close(state.win, true)
    end
    local project = require("wyt.project")
    if not project.setup() then return end
    if valid() then pcall(vim.api.nvim_win_close, state.win, true) end
    state.root = project.project_root
    if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then state.buf = make_buf() end
    state.win = vim.api.nvim_open_win(state.buf, false, { split = "left", win = -1, width = WIDTH })
    for k, v in pairs(WIN_OPTS) do vim.api.nvim_set_option_value(k, v, { scope = "local", win = state.win }) end
    vim.api.nvim_set_current_win(state.win)
end

return M
