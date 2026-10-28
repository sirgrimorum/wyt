-- The wyt markers a writer leaves in a text: what counts as one, where it
-- starts and ends, and what an answer does to the line around it.
local markers = require("wyt.markers")

local function texts(line)
    return vim.tbl_map(function(m) return m.text end, markers.find(line))
end

describe("markers.find", function()
    it("finds both forms, in order, with the columns of the whole marker", function()
        local line = "In WYT: the year :wyt the law, and wyt(her name) said"
        local got = markers.find(line)
        assert.same({ "the year", "her name" }, vim.tbl_map(function(m) return m.text end, got))
        assert.equals("WYT: the year :wyt", line:sub(got[1].s, got[1].e))
        assert.equals(got[1].raw, line:sub(got[1].s, got[1].e))
        assert.equals("wyt(her name)", got[2].raw)
    end)

    it("ignores case, which handwriting recognition sets at random", function()
        assert.same({ "the year" }, texts("Wyt: the year :WYT."))
        assert.same({ "a name" }, texts("WYT(a name)"))
    end)

    it("runs a marker left open to the end of its line", function()
        local got = markers.find("She said wyt: what she said")
        assert.equals("what she said", got[1].text)
        assert.equals(#"She said wyt: what she said", got[1].e)
    end)

    it("keeps its columns true past accents", function()
        local line = "¿Quién? wyt: el año :WYT."
        local got = markers.find(line)
        assert.equals("el año", got[1].text)
        assert.equals("wyt: el año :WYT", line:sub(got[1].s, got[1].e))
    end)

    it("takes no part of a longer word, and no empty marker", function()
        assert.same({}, texts("The newyt: thing :wyt"))
        assert.same({}, texts("wyt: :wyt and wyt()"))
        assert.same({}, texts("Nothing to see here."))
    end)
end)

describe("markers.in_lines", function()
    it("numbers each marker by its line and skips text parked in an old fence", function()
        local lines = { "wyt(one)", "```old", "wyt(parked)", "```", "two wyt: three" }
        local status = require("wyt.status")
        local got = markers.in_lines(lines, status.parked(lines))
        assert.same({ { 1, "one" }, { 5, "three" } },
            vim.tbl_map(function(m) return { m.line, m.text } end, got))
    end)
end)

describe("markers.replace", function()
    it("puts the answer where the marker was, inside a sentence on one line", function()
        local line = "It was wyt: the year :wyt when the law passed."
        local m = markers.find(line)[1]
        assert.same({ "It was 1912 when the law passed." }, markers.replace(line, m, "1912"))
        assert.same({ "It was the spring of 1912 when the law passed." },
            markers.replace(line, m, "the spring\nof 1912"))
    end)

    it("lets a marker alone on its line take paragraphs", function()
        local line = "  wyt(what the gate looked like)"
        local m = markers.find(line)[1]
        assert.same({ "It was iron.", "", "It was chained." }, markers.replace(line, m, "It was iron.\n\nIt was chained."))
    end)
end)
