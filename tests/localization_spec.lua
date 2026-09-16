-- localization.lua. The parity check is the one that matters: a key added to
-- English and forgotten in Spanish shows up as an English string in the middle
-- of a Spanish prompt, which nothing else in the suite would catch.
local loc = require("wyt.localization")

describe("the two languages cover the same keys", function()
    it("has no key in English that Spanish is missing", function()
        local missing = {}
        for key in pairs(loc.translations.en) do
            if loc.translations.es[key] == nil then missing[#missing + 1] = key end
        end
        table.sort(missing)
        assert.equals("", table.concat(missing, ", "), "untranslated into Spanish")
    end)

    it("has no key in Spanish that English is missing", function()
        local missing = {}
        for key in pairs(loc.translations.es) do
            if loc.translations.en[key] == nil then missing[#missing + 1] = key end
        end
        table.sort(missing)
        assert.equals("", table.concat(missing, ", "), "present only in Spanish")
    end)

    it("leaves no value empty in either language", function()
        for lang, table_ in pairs(loc.translations) do
            for key, value in pairs(table_) do
                assert.truthy(value ~= nil and value ~= "", lang .. "." .. key .. " is empty")
            end
        end
    end)
end)

describe("loc.t", function()
    it("returns the string for the language asked for", function()
        assert.equals("Ideas", loc.t("ideas_section", "en"))
        assert.equals("Description", loc.t("description_section", "en"))
        assert.equals("Descripción", loc.t("description_section", "es"))
    end)

    it("translates the group marker, which is parsed back out of files", function()
        assert.equals("Group", loc.t("group_tag", "en"))
        assert.equals("Grupo", loc.t("group_tag", "es"))
    end)

    it("falls back to English for a language it does not have", function()
        assert.equals("Ideas", loc.t("ideas_section", "de"))
    end)

    it("returns the key itself for a key that does not exist", function()
        assert.equals("no_such_key_anywhere", loc.t("no_such_key_anywhere", "en"))
    end)
end)

describe("loc.set_lang and get_lang", function()
    it("round-trips the current language", function()
        local before = loc.get_lang()
        loc.set_lang("es")
        assert.equals("es", loc.get_lang())
        loc.set_lang(before)
    end)
end)

describe("loc.pad", function()
    it("leaves a trailing space, so an input prompt does not touch its answer", function()
        assert.matches(" $", loc.pad("Idea name:"))
    end)
end)

describe("the placeholder marker", function()
    it("ends with a separator in both languages, since the idea follows it", function()
        assert.matches(":%s$", loc.translations.en.create_paragraph)
        assert.matches(":%s$", loc.translations.es.create_paragraph)
    end)
end)
