-- Inline markers: a gap left so the writing can go on, `wyt: the year the law
-- passed :wyt` or `wyt(the sister's name)`. Rare enough in prose to need no
-- escape, and easy to write by hand on the Boox, unlike `??`. Case is
-- ignored, since handwriting recognition capitalises at random, and a marker
-- left open runs to the end of its line.
local M = {}

local OPEN = { colon = "%f[%w_]wyt%s*:", paren = "%f[%w_]wyt%s*%(" }
local CLOSE = { colon = ":%s*wyt%f[^%w_]", paren = "%)" }

--- The markers in `line`, in order: { s, e, raw, text }, with `s` and `e` the
--- byte columns of the whole marker and `text` what it asks, trimmed. An empty
--- marker asks nothing and is not one.
function M.find(line)
    -- Searched lowercased: string.lower is byte-wise and only touches ASCII, so
    -- every column found there holds in the line itself, accents included.
    local low = line:lower()
    local out, pos = {}, 1
    while true do
        local s, e, kind
        for k, pat in pairs(OPEN) do
            local ks, ke = low:find(pat, pos)
            if ks and (not s or ks < s) then s, e, kind = ks, ke, k end
        end
        if not s then return out end
        local cs, ce = low:find(CLOSE[kind], e + 1)
        local inner_end = cs and cs - 1 or #line
        local stop = ce or #line
        local text = vim.trim(line:sub(e + 1, inner_end))
        if text ~= "" then out[#out + 1] = { s = s, e = stop, raw = line:sub(s, stop), text = text } end
        pos = stop + 1
    end
end

--- Every marker in `lines`, as { line, s, e, raw, text }, leaving out the
--- lines in `parked` (an ```old fence): text set aside is not text to finish.
function M.in_lines(lines, parked)
    local out = {}
    for i, line in ipairs(lines) do
        if not (parked and parked[i]) then
            for _, m in ipairs(M.find(line)) do
                m.line = i
                out[#out + 1] = m
            end
        end
    end
    return out
end

--- `line` with marker `m` replaced by `answer`. A marker alone on its line may
--- take paragraphs; inside a sentence the answer is run onto one line.
--- Returns a list of lines.
function M.replace(line, m, answer)
    local before, after = line:sub(1, m.s - 1), line:sub(m.e + 1)
    if vim.trim(before) == "" and vim.trim(after) == "" then
        return vim.split(answer, "\n", { plain = true })
    end
    return { before .. answer:gsub("%s*\n%s*", " ") .. after }
end

return M
