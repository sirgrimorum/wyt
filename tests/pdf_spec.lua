-- The hand-written PDF. What a reader needs to open it is checked here: the
-- text in the font's encoding, lines that fit the page, and a cross-reference
-- table whose offsets land on the objects.
local pdf = require("wyt.pdf")

describe("pdf.encode", function()
    it("keeps ASCII and turns Latin-1 into single bytes", function()
        assert.equals("plain", pdf.encode("plain"))
        assert.equals("\191Qu\233?", pdf.encode("¿Qué?"))
        assert.equals("\161\171\187\241", pdf.encode("¡«»ñ"))
    end)

    it("maps the common characters past Latin-1 and prints the rest as ?", function()
        assert.equals("\147a\148 \150 \155", pdf.encode("“a” – ›"))
        assert.equals("?", pdf.encode("漢"))
    end)

    it("reads a tab or a CR as a space, so the words still wrap apart", function()
        assert.equals("a b c ", pdf.encode("a\tb c\r"))
        assert.same({ "a", "b" }, pdf.wrap(pdf.encode("a\tb\r"), 13, 5))
    end)
end)

describe("pdf.wrap", function()
    it("breaks at spaces before the width, and keeps a short line whole", function()
        assert.same({ "short line" }, pdf.wrap("short line", 13, 300))
        -- An `m` at 13 pt is 10.8 pt wide: three and a space fit 40, not four.
        assert.same({ "mmm", "mmm" }, pdf.wrap("mmm mmm", 13, 40))
    end)

    it("measures the accented capitals and the wide marks at their own width", function()
        -- At 10 pt `Ó Ó` is 18.3 wide, `… …` 22.8 and `é é` 13.9; one width for
        -- every byte past ASCII made all three 16.1.
        assert.same({ pdf.encode("Ó"), pdf.encode("Ó") }, pdf.wrap(pdf.encode("Ó Ó"), 10, 17))
        assert.same({ pdf.encode("…"), pdf.encode("…") }, pdf.wrap(pdf.encode("… …"), 10, 20))
        assert.same({ pdf.encode("é é") }, pdf.wrap(pdf.encode("é é"), 10, 14))
    end)

    it("lets a word longer than the line run past it", function()
        assert.same({ "a", ("m"):rep(40), "b" }, pdf.wrap("a " .. ("m"):rep(40) .. " b", 13, 100))
    end)
end)

describe("pdf.render", function()
    local function offsets(bytes)
        local start = tonumber(bytes:match("startxref\n(%d+)"))
        local out = {}
        for off in bytes:sub(start + 1):gmatch("(%d%d%d%d%d%d%d%d%d%d) 00000 n ") do
            out[#out + 1] = tonumber(off)
        end
        return out, start
    end

    it("writes a PDF whose xref points at each object", function()
        local bytes, pages = pdf.render("Title (draft)", "2026-10-28", "One line.\n\nAnother \\ one.")
        assert.equals(1, pages)
        assert.equals("%PDF-1.4", bytes:sub(1, 8))
        assert.equals("%%EOF\n", bytes:sub(-6))
        local list, start = offsets(bytes)
        assert.equals(6, #list)
        for i, off in ipairs(list) do
            assert.equals(i .. " 0 obj", bytes:sub(off + 1, off + #(i .. " 0 obj")))
        end
        assert.equals("xref", bytes:sub(start + 1, start + 4))
        -- The bytes `encode` writes mean Latin-1 only under this encoding, and
        -- the page is the Boox screen's 3:4.
        local _, fonts = bytes:gsub("/Encoding /WinAnsiEncoding", "")
        assert.equals(2, fonts)
        local w, h = bytes:match("/MediaBox %[0 0 (%d+) (%d+)%]")
        assert.truthy(math.abs(tonumber(w) / tonumber(h) - 0.75) < 0.01)
        -- Parentheses and backslashes would end or bend the string in the stream.
        assert.truthy(bytes:find("(Title \\(draft\\)) Tj", 1, true))
        assert.truthy(bytes:find("(Another \\\\ one.) Tj", 1, true))
    end)

    it("gives each stream its real length", function()
        local bytes = pdf.render("T", nil, "x")
        local len, body = bytes:match("/Length (%d+) >>\nstream\n(.-)\nendstream")
        assert.equals(#body, tonumber(len))
    end)

    it("starts a new page when the text runs past the bottom", function()
        local lines = {}
        for i = 1, 40 do lines[i] = "Line " .. i end
        local bytes, pages = pdf.render("T", nil, table.concat(lines, "\n"))
        assert.equals(2, pages)
        assert.truthy(bytes:find("/Count 2", 1, true))
        assert.equals(8, #offsets(bytes))
    end)
end)
