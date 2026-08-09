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
--- (headless, tiny screen, older UI); callers fall back to an inline prompt.
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

    local ok, win = pcall(vim.api.nvim_open_win, buf, false, {
        relative = "editor",
        width = width,
        height = math.min(#padded, 10),
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

function M.close(win)
    if win and vim.api.nvim_win_is_valid(win) then
        pcall(vim.api.nvim_win_close, win, true)
    end
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
--- when no float could be opened (headless, tiny screen).
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
