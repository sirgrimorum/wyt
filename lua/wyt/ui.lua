-- Helpers for showing text that a selection prompt would truncate.
-- vim.ui.select renders its `prompt` as a single line, so a generated sentence
-- passed as the prompt is cut off. The text goes in a panel above the menu and
-- the prompt keeps a short, fixed title.
local M = {}

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

return M
