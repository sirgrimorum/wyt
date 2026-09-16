-- Helpers for showing text that a selection prompt would truncate.
-- vim.ui.select renders its `prompt` as a single line, so a generated sentence
-- passed as the prompt is cut off. The text goes in a panel above the menu and
-- the prompt keeps a short, fixed title.
local loc = require("wyt.localization")

local M = {}

-- A prompt is drawn as a title: on the command line by the built-in pickers, as
-- a window title by dressing/telescope/snacks, where the window is sized to its
-- items and not to the question. Past this many cells a question stops being a
-- title and has to become a description.
local TITLE_BUDGET = 48

--- Shorten `str` to `width` display cells, ellipsis included.
function M.truncate(str, width)
    if vim.fn.strdisplaywidth(str) <= width then return str end
    return vim.fn.strcharpart(str, 0, width - 1) .. "…"
end

--- Fit `text` after `prefix` on one command line, so a confirmation never
--- overflows into Neovim's "Press ENTER" prompt.
function M.fit_message(prefix, text)
    local budget = math.max(20, vim.o.columns - vim.fn.strdisplaywidth(prefix) - 2)
    return prefix .. M.truncate(text, budget)
end

--- Word-wrap `text` to `width` display cells. Multibyte safe.
function M.wrap(text, width)
    local lines = {}
    for _, paragraph in ipairs(vim.split(text, "\n", { plain = true })) do
        local line = ""
        for word in paragraph:gmatch("%S+") do
            if line == "" then
                line = word
            elseif vim.fn.strdisplaywidth(line .. " " .. word) <= width then
                line = line .. " " .. word
            else
                lines[#lines + 1] = line
                line = word
            end
        end
        lines[#lines + 1] = line
    end
    return lines
end

--- Non-focusable panel centred at the top of the editor.
--- Returns a window handle for M.close, or nil when no float could be opened
--- (a screen under 38 columns); callers fall back to an inline prompt.
function M.preview(title, text)
    local width = math.min(76, vim.o.columns - 8)
    if width < 30 then return nil end

    local lines = M.wrap(text, width - 2)
    local padded = {}
    for i, l in ipairs(lines) do padded[i] = " " .. l end

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, padded)
    vim.bo[buf].modifiable = false
    vim.bo[buf].bufhidden = "wipe"

    -- The panel takes no focus, so nothing past its last line can be scrolled
    -- to: a question longer than a fixed ten lines was simply cut off. Give it
    -- what the screen has, leaving the menu underneath room to open.
    local max_height = math.max(5, vim.o.lines - 12)

    local ok, win = pcall(vim.api.nvim_open_win, buf, false, {
        relative = "editor",
        width = width,
        height = math.min(#padded, max_height),
        row = 1,
        col = math.floor((vim.o.columns - width) / 2),
        style = "minimal",
        border = "rounded",
        title = " " .. title .. " ",
        title_pos = "center",
        focusable = false,
        noautocmd = true,
    })
    if not ok then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
        return nil
    end
    vim.wo[win].wrap = false
    vim.cmd("redraw")
    return win
end

--- Close a panel. Takes the nil M.preview returns on a narrow screen, so no
--- caller has to check first.
function M.close(win)
    if win and vim.api.nvim_win_is_valid(win) then
        pcall(vim.api.nvim_win_close, win, true)
    end
end

-- Windows hands the same file back with either separator, and its filesystem
-- does not care about case, so paths are compared through this.
local function canonical(path)
    local full = vim.fn.fnamemodify(path, ":p"):gsub("\\", "/")
    if vim.fn.has("win32") == 1 then full = full:lower() end
    return full
end

--- Write the current buffer if it has unsaved changes.
--- Navigation moves between files of one project, and an edit that was never
--- written is lost to the move. Writing also fires the auto-commit, so the step
--- is recorded like any other save.
function M.save_current()
    local buf = vim.api.nvim_get_current_buf()
    if vim.bo[buf].buftype ~= "" then return end
    if not vim.bo[buf].modified or vim.bo[buf].readonly then return end
    if vim.api.nvim_buf_get_name(buf) == "" then return end
    pcall(vim.cmd, "silent write")
end

--- Jump to the window already showing `path`, in any tab. True when it found one.
local function focus_existing(path)
    local target = canonical(path)
    -- This tab's windows first. A file open both here and in a tab the writer
    -- left behind should not pull them out of the tab they are working in.
    local wins = vim.api.nvim_tabpage_list_wins(0)
    vim.list_extend(wins, vim.api.nvim_list_wins())
    for _, win in ipairs(wins) do
        local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
        if name ~= "" and canonical(name) == target then
            vim.fn.win_gotoid(win)
            -- The file may have been rewritten on disk while it sat in that tab
            vim.cmd("silent! checktime")
            return true
        end
    end
    return false
end

--- Open `path` in a tab of its own, saving the current buffer first.
--- A file already on screen is jumped to rather than opened again: navigating
--- back and forth between a plan and its section used to leave a new tab behind
--- every time. Only a file that is nowhere yet gets a new tab.
function M.open_file(path)
    M.save_current()
    if focus_existing(path) then return end
    vim.cmd("tabnew " .. vim.fn.fnameescape(path))
end

--- Open `path` in the current window, saving what is there first.
--- Still prefers a window that already shows the file, so a command cannot put
--- the same file on screen twice.
function M.edit_file(path)
    M.save_current()
    if focus_existing(path) then return end
    vim.cmd("edit " .. vim.fn.fnameescape(path))
end

--- True when `text` is too long, or too many lines, to be read as a prompt.
function M.needs_panel(text)
    if text:find("\n", 1, true) then return true end
    local budget = math.min(TITLE_BUDGET, math.max(20, vim.o.columns - 8))
    return vim.fn.strdisplaywidth(text) > budget
end

--- Decide where `q.question` is shown. Returns the panel, if one was opened, and
--- the prompt to use with it: the question itself while it still fits, the short
--- `q.title` (or `q.prompt`, when the menu has to ask something the title does
--- not) once the panel carries the text, and the question labelled with the title
--- when no float could be opened (a screen too narrow for one).
local function place(q)
    if not M.needs_panel(q.question) then return nil, q.question end
    local panel = M.preview(q.title, q.question)
    if panel then return panel, q.prompt or q.title end
    return nil, q.title .. ": " .. (q.question:gsub("%s*\n%s*", " "))
end

--- Ask `q.question`, answered by picking one of `items`.
--- A question short enough to read as a title is the prompt, as before. A longer
--- one moves into a panel titled `q.title`, so the menu is never handed a
--- sentence it would cut off.
--- `q` is { title = short label, question = full text, prompt = menu prompt when
--- the panel is showing, defaults to the title }.
function M.ask_select(q, items, on_choice)
    local panel, prompt = place(q)
    vim.ui.select(items, { prompt = prompt }, function(choice)
        M.close(panel)
        on_choice(choice)
    end)
end

--- Same, for a question answered by typing. `q.default` pre-fills the answer.
--- The prompt is padded here, so callers pass raw text.
function M.ask_input(q, on_input)
    local panel, prompt = place(q)
    vim.ui.input({ prompt = loc.pad(prompt), default = q.default }, function(answer)
        M.close(panel)
        on_input(answer)
    end)
end

return M
