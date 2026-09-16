-- ui.lua's text fitting, and how it opens files. Headless Neovim does open a
-- float at its default 80 columns, so the nil fallback is checked by shrinking
-- the screen below what a panel needs.
local helpers = require("tests.helpers")
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
        -- Width 3 keeps two characters; a byte cut would end inside the é.
        assert.equals("aé…", ui.truncate("aéxyz", 3))
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

describe("ui.open_file", function()
    local root

    before_each(function()
        helpers.cleanup(root)
        root = helpers.project({ type = "essay" })
        vim.cmd("silent! tabonly")
    end)

    it("saves the buffer it leaves, so a jump never loses an edit", function()
        helpers.write(root .. "a.md", "old\n")
        helpers.write(root .. "b.md", "b\n")
        vim.cmd("edit " .. vim.fn.fnameescape(root .. "a.md"))
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "unsaved edit" })
        ui.open_file(root .. "b.md")
        assert.equals("unsaved edit\n", helpers.read(root .. "a.md"))
    end)

    it("goes back to the tab a file is already in instead of opening another", function()
        helpers.write(root .. "a.md", "a\n")
        helpers.write(root .. "b.md", "b\n")
        vim.cmd("edit " .. vim.fn.fnameescape(root .. "a.md"))
        ui.open_file(root .. "b.md")
        local tabs = #vim.api.nvim_list_tabpages()
        ui.open_file(root .. "a.md")
        assert.equals(tabs, #vim.api.nvim_list_tabpages())
        assert.matches("a%.md$", vim.api.nvim_buf_get_name(0))
    end)

    -- Windows are listed across every tab, so the same file open in a tab left
    -- behind used to win over the split right next to the writer.
    it("stays in this tab when the file is on screen here too", function()
        helpers.write(root .. "a.md", "a\n")
        vim.cmd("edit " .. vim.fn.fnameescape(root .. "a.md"))
        vim.cmd("tabnew " .. vim.fn.fnameescape(root .. "a.md"))
        local here = vim.api.nvim_get_current_tabpage()
        ui.open_file(root .. "a.md")
        assert.equals(here, vim.api.nvim_get_current_tabpage())
    end)
end)

describe("ui.preview", function()
    -- Nothing can scroll a panel that takes no focus, so a long question used to
    -- lose everything past its tenth line.
    it("grows past ten lines for a long question", function()
        local win = ui.preview("Title", string.rep("palabra ", 400))
        local height = vim.api.nvim_win_get_height(win)
        ui.close(win)
        assert.truthy(height > 10)
        -- and still leaves the screen room for the menu underneath
        assert.truthy(height <= vim.o.lines - 10)
    end)

    it("returns nil rather than erroring when no float can be opened", function()
        local columns = vim.o.columns
        vim.o.columns = 20
        assert.is_nil(ui.preview("Title", "Some text"))
        vim.o.columns = columns
    end)
end)
