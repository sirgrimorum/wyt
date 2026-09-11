-- ui.lua's text fitting. The float itself is not opened here: headless Neovim
-- has no usable screen, which is exactly the case `preview` is written to
-- return nil for, and the callers fall back to an inline prompt.
local ui = require("wyt.ui")

describe("ui.truncate", function()
    it("leaves text that already fits", function()
        assert.equals("short", ui.truncate("short", 20))
    end)

    it("cuts to the budget, ellipsis included", function()
        local out = ui.truncate("a sentence that is definitely too long", 10)
        assert.truthy(vim.fn.strdisplaywidth(out) <= 10)
        assert.matches("…$", out)
    end)

    it("counts display cells, not bytes, so accents do not shorten it", function()
        local accented = "árbol árbol árbol"
        assert.equals(accented, ui.truncate(accented, vim.fn.strdisplaywidth(accented)))
    end)

    it("never splits a multibyte character in half", function()
        local out = ui.truncate("¿Qué ocurre a continuación en tu historia?", 12)
        assert.equals(out, vim.fn.strcharpart(out, 0))
    end)
end)

describe("ui.wrap", function()
    it("breaks on words, never mid-word", function()
        for _, line in ipairs(ui.wrap("the quick brown fox jumps over it", 12)) do
            assert.truthy(vim.fn.strdisplaywidth(line) <= 12, "too wide: " .. line)
        end
    end)

    it("keeps every word", function()
        local joined = table.concat(ui.wrap("the quick brown fox", 8), " ")
        assert.equals("the quick brown fox", joined)
    end)

    it("keeps paragraph breaks", function()
        assert.equals(2, #ui.wrap("first\nsecond", 40))
    end)

    it("does not lose a word longer than the width", function()
        assert.same({ "supercalifragilistic" }, ui.wrap("supercalifragilistic", 5))
    end)
end)

describe("ui.fit_message", function()
    it("keeps the prefix and fits the rest on one line", function()
        local out = ui.fit_message("[WYT] ", string.rep("word ", 200))
        assert.matches("^%[WYT%] ", out)
        assert.truthy(vim.fn.strdisplaywidth(out) <= vim.o.columns)
    end)
end)

describe("ui.needs_panel", function()
    it("is true for anything with a line break in it", function()
        assert.truthy(ui.needs_panel("first line\nsecond line"))
    end)

    it("is true for a question too long to read as a title", function()
        assert.truthy(ui.needs_panel(string.rep("word ", 40)))
    end)

    it("is false for a short question, which stays on the prompt line", function()
        assert.falsy(ui.needs_panel("Idea name:"))
    end)
end)

describe("ui.preview", function()
    it("returns nil rather than erroring when no float can be opened", function()
        local columns = vim.o.columns
        vim.o.columns = 20
        assert.is_nil(ui.preview("Title", "Some text"))
        vim.o.columns = columns
    end)
end)
