-- idea.lua drives the brainstorm: what it tells the writer about the project,
-- and what it does with the answers it collects.
local helpers = require("tests.helpers")
local loc = require("wyt.localization")

describe("idea.new_idea guided questions", function()
    local root

    before_each(function() helpers.cleanup(root) end)

    -- The writer picked "Novela larga" in the wizard and has never seen the id.
    it("names the type the way the writer chose it, not by its id", function()
        root = helpers.project({ type = "long_novel", lang = "es" })
        loc.set_lang("es")
        local messages = helpers.capture_notify()
        local _, restore = helpers.scripted_ui({ loc.t("answer_questions"), nil })
        require("wyt.idea").new_idea()
        restore()
        local shown = messages[1] and messages[1].msg or ""
        assert.matches("Novela larga", shown)
        assert.has_no_match("long_novel", shown)
    end)
end)
