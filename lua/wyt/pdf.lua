-- A PDF from plain text, written by hand: the brief on the Boox needs a title,
-- wrapped lines and pages, and a font every reader has built in gives that
-- without a dependency. Helvetica in WinAnsi covers Spanish; the few common
-- characters past Latin-1 in `WINANSI` (curly quotes, dashes, `…`, `•`, `€`,
-- `‹ ›`) are mapped, anything else prints as `?`.
local M = {}

-- 3:4, the shape of the Boox screen, so a page fills it without zooming.
local W, H, MARGIN = 446, 595, 36
local SIZE, TITLE, LEAD = 13, 20, 1.45

-- Helvetica's advance widths in thousandths of an em, ASCII 32 to 126.
local WIDTHS = {
    278, 278, 355, 556, 556, 889, 667, 191, 333, 333, 389, 584, 278, 333, 278, 278,
    556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 278, 278, 584, 584, 584, 556,
    1015, 667, 667, 722, 722, 667, 611, 778, 722, 278, 500, 667, 556, 833, 722, 778,
    667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 278, 278, 278, 469, 556,
    333, 556, 556, 500, 556, 556, 278, 556, 556, 222, 222, 500, 222, 833, 556, 556,
    556, 556, 333, 500, 278, 556, 500, 722, 500, 500, 500, 334, 260, 334, 584,
}
-- Latin-1, 160 to 255: the accented capitals are wider than the plain ones,
-- and a guess would let a line of `Ó` and `Ñ` run past the margin.
local LATIN1 = {
    278, 333, 556, 556, 556, 556, 260, 556, 333, 737, 370, 556, 584, 333, 737, 333,
    400, 584, 333, 333, 333, 556, 537, 278, 333, 333, 365, 556, 834, 834, 834, 611,
    667, 667, 667, 667, 667, 667, 1000, 722, 667, 667, 667, 667, 278, 278, 278, 278,
    722, 722, 778, 778, 778, 778, 778, 584, 778, 722, 722, 722, 722, 667, 667, 611,
    556, 556, 556, 556, 556, 556, 889, 500, 556, 556, 556, 556, 278, 278, 278, 278,
    556, 556, 556, 556, 556, 556, 556, 584, 611, 556, 556, 556, 556, 500, 556, 500,
}
-- The WinAnsi bytes below 160 that `encode` produces.
local HIGH = {
    [0x80] = 556, [0x82] = 222, [0x85] = 1000, [0x8B] = 333, [0x91] = 222, [0x92] = 222,
    [0x93] = 333, [0x94] = 333, [0x95] = 350, [0x96] = 556, [0x97] = 1000, [0x9B] = 333,
}

local WINANSI = {
    [0x20AC] = 0x80, [0x201A] = 0x82, [0x2026] = 0x85, [0x2039] = 0x8B,
    [0x2018] = 0x91, [0x2019] = 0x92, [0x201C] = 0x93, [0x201D] = 0x94,
    [0x2022] = 0x95, [0x2013] = 0x96, [0x2014] = 0x97, [0x203A] = 0x9B,
}

--- `text`, UTF-8, as the WinAnsi bytes the font reads.
function M.encode(text)
    local out = {}
    for _, c in ipairs(vim.fn.str2list(text, true)) do
        -- A tab or a stray CR is a space to `wrap`, not a `?` gluing two words.
        if c == 9 or c == 10 or c == 13 then c = 32 end
        local b = (c >= 32 and c < 127 or c >= 160 and c < 256) and c or WINANSI[c] or 63
        out[#out + 1] = string.char(b)
    end
    return table.concat(out)
end

local function width(bytes, size)
    local w = 0
    for i = 1, #bytes do
        local b = bytes:byte(i)
        w = w + (b < 127 and WIDTHS[b - 31] or b >= 160 and LATIN1[b - 159] or HIGH[b])
    end
    return w * size / 1000
end

--- `line`, already encoded, broken at spaces into lines `max` points wide at
--- `size`. A word longer than a line runs past the margin rather than split.
function M.wrap(line, size, max)
    local out, cur = {}, nil
    for word in line:gmatch("%S+") do
        local try = cur and (cur .. " " .. word) or word
        if cur and width(try, size) > max then
            out[#out + 1], cur = cur, word
        else
            cur = try
        end
    end
    out[#out + 1] = cur or ""
    return out
end

--- The bytes of a PDF: `title` in bold, `subtitle` under it, then `text` one
--- line per line, wrapped, a blank line leaving space between paragraphs.
function M.render(title, subtitle, text)
    local pages, ops, y = {}, nil, 0
    local function new_page()
        ops, y = {}, H - MARGIN
        pages[#pages + 1] = ops
    end
    local function put(font, size, s)
        if y - size * LEAD < MARGIN then new_page() end
        y = y - size * LEAD
        local escaped = s:gsub("[\\()]", "\\%0")
        ops[#ops + 1] = ("BT /%s %d Tf %d %.1f Td (%s) Tj ET"):format(font, size, MARGIN, y, escaped)
    end
    new_page()
    -- Bold runs about a tenth wider than the table.
    for _, l in ipairs(M.wrap(M.encode(title), TITLE * 1.1, W - 2 * MARGIN)) do put("F2", TITLE, l) end
    if subtitle then put("F1", SIZE, M.encode(subtitle)) end
    for _, line in ipairs(vim.split(text, "\n", { plain = true })) do
        if vim.trim(line) == "" then
            y = y - SIZE * LEAD / 2
        else
            for _, l in ipairs(M.wrap(M.encode(line), SIZE, W - 2 * MARGIN)) do put("F1", SIZE, l) end
        end
    end

    local objs = {
        "<< /Type /Catalog /Pages 2 0 R >>",
        "",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>",
    }
    local kids = {}
    for _, page in ipairs(pages) do
        local stream = table.concat(page, "\n")
        objs[#objs + 1] = ("<< /Length %d >>\nstream\n%s\nendstream"):format(#stream, stream)
        objs[#objs + 1] = ("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %d %d]"
            .. " /Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> /Contents %d 0 R >>"):format(W, H, #objs)
        kids[#kids + 1] = #objs .. " 0 R"
    end
    objs[2] = ("<< /Type /Pages /Kids [%s] /Count %d >>"):format(table.concat(kids, " "), #kids)

    -- The cross-reference table gives each object's byte offset, so a reader
    -- can open the file without parsing it front to back.
    local out = { "%PDF-1.4\n%\226\227\207\211\n" }
    local size, xref = #out[1], { "xref", "0 " .. (#objs + 1), "0000000000 65535 f " }
    for i, body in ipairs(objs) do
        xref[#xref + 1] = ("%010d 00000 n "):format(size)
        out[#out + 1] = ("%d 0 obj\n%s\nendobj\n"):format(i, body)
        size = size + #out[#out]
    end
    out[#out + 1] = table.concat(xref, "\n") .. "\n"
        .. ("trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n"):format(#objs + 1, size)
    return table.concat(out), #pages
end

return M
