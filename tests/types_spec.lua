-- types.lua: the per-type table is the plugin's whole configuration surface, so
-- these check every type rather than a representative one. A type that is added
-- without its guides is the failure this file exists to catch.
local types = require("wyt.types")

local LANGS = { "en", "es" }

describe("types.names", function()
    it("offers the six types the guide documents, in wizard order", function()
        assert.same({ "novel", "long_novel", "short_novel", "short_story", "essay", "summary" },
            types.names())
    end)

    it("names only types that exist", function()
        for _, id in ipairs(types.names()) do
            assert.is_not_nil(types.configs[id], id .. " is offered but not configured")
        end
    end)
end)

describe("every type is fully configured", function()
    local localized_fields = {
        "label", "blurb", "prose_kind", "idea_prompt", "subsection_idea_prompt",
        "group_prompt", "group_name_hint",
    }

    it("defines every localized field in both languages", function()
        for _, id in ipairs(types.names()) do
            for _, field in ipairs(localized_fields) do
                local entry = types.configs[id][field]
                assert.is_not_nil(entry, id .. " has no " .. field)
                for _, lang in ipairs(LANGS) do
                    local value = entry[lang]
                    assert.truthy(value and value ~= "",
                        id .. "." .. field .. " is missing " .. lang)
                end
            end
        end
    end)

    it("defines question lists in both languages", function()
        for _, id in ipairs(types.names()) do
            for _, field in ipairs({ "idea_questions" }) do
                for _, lang in ipairs(LANGS) do
                    local list = types.configs[id][field][lang]
                    assert.truthy(list and #list > 0, id .. "." .. field .. " is empty in " .. lang)
                end
            end
        end
    end)

    it("declares a depth, a paragraph rule and an archetype set", function()
        for _, id in ipairs(types.names()) do
            local cfg = types.configs[id]
            assert.truthy(cfg.section_depth >= 1, id .. " has no usable section_depth")
            assert.equals("boolean", type(cfg.multi_idea_paragraph), id .. ".multi_idea_paragraph")
            assert.truthy(#cfg.section_kinds > 0, id .. " has no section_kinds")
        end
    end)
end)

describe("types.label", function()
    it("translates the id, in both languages", function()
        assert.equals("Long novel", types.label("long_novel", "en"))
        assert.equals("Novela larga", types.label("long_novel", "es"))
        assert.equals("Cuento", types.label("short_story", "es"))
    end)

    it("never leaks an id, which is English and holds an underscore", function()
        for _, lang in ipairs(LANGS) do
            for _, id in ipairs(types.names()) do
                assert.has_no_match("_", types.label(id, lang))
            end
        end
    end)

    it("falls back to English for a language it has no entry for", function()
        assert.equals("Novel", types.label("novel", "de"))
    end)
end)

describe("types.menu_label", function()
    it("reads as the name, then what the type does to the text", function()
        assert.equals("Essay: Titled sections, their paragraphs running on.",
            types.menu_label("essay", "en"))
    end)

    it("shows no id for any type in any language", function()
        for _, lang in ipairs(LANGS) do
            for _, id in ipairs(types.names()) do
                assert.has_no_match("_", types.menu_label(id, lang))
            end
        end
    end)
end)

describe("types.prose_kind", function()
    it("asks for the paragraph the type actually wants", function()
        assert.equals("a narrative paragraph", types.prose_kind("novel", "en"))
        assert.equals("un párrafo argumentativo", types.prose_kind("essay", "es"))
        assert.equals("un párrafo de notas conciso", types.prose_kind("summary", "es"))
    end)

    it("is a noun phrase with its article, so it drops into a sentence", function()
        for _, id in ipairs(types.names()) do
            assert.matches("^a[n]? ", types.prose_kind(id, "en"))
            assert.matches("^un ", types.prose_kind(id, "es"))
        end
    end)
end)

describe("an unknown type behaves as an essay", function()
    it("resolves the config, not a raw copy of the id", function()
        assert.equals(types.configs.essay, types.get("nonsense"))
        assert.equals("Ensayo", types.label("nonsense", "es"))
        assert.equals(2, types.section_depth("nonsense"))
    end)

    it("catches the underscore bug: short_story must not read as short", function()
        assert.equals(1, types.section_depth("short_story"))
        assert.equals("Cuento", types.label("short_story", "es"))
    end)
end)

describe("types.section_depth", function()
    it("matches the depth each type is documented with", function()
        assert.equals(3, types.section_depth("novel"))
        assert.equals(4, types.section_depth("long_novel"))
        assert.equals(2, types.section_depth("short_novel"))
        assert.equals(1, types.section_depth("short_story"))
        assert.equals(2, types.section_depth("essay"))
        assert.equals(1, types.section_depth("summary"))
    end)
end)

describe("types.outline", function()
    it("titles novel chapters and separates its scenes", function()
        assert.same({ heading = 2 }, types.outline("novel", 2))
        assert.same({ break_with = "* * *" }, types.outline("novel", 3))
    end)

    it("gives a long novel one more titled level than a novel", function()
        assert.same({ heading = 2 }, types.outline("long_novel", 2))
        assert.same({ heading = 3 }, types.outline("long_novel", 3))
        assert.same({ break_with = "* * *" }, types.outline("long_novel", 4))
    end)

    it("never titles a short novel's scenes", function()
        assert.same({ break_with = "* * *" }, types.outline("short_novel", 2))
    end)

    it("declares nothing for level 1, which is always the document title", function()
        for _, id in ipairs(types.names()) do
            assert.is_nil(types.outline(id, 1))
        end
    end)

    it("returns nil past the map, so an extra level comes out untitled", function()
        assert.is_nil(types.outline("essay", 3))
        assert.is_nil(types.outline("novel", 4))
    end)
end)

describe("types.group_outline", function()
    it("labels a summary's groups, since notes read better labelled", function()
        assert.same({ heading = 2 }, types.group_outline("summary"))
    end)

    it("separates a short story's groups instead of titling them", function()
        assert.same({ break_with = "* * *" }, types.group_outline("short_story"))
    end)

    it("renders nothing for types whose group markers are pure structure", function()
        assert.is_nil(types.group_outline("novel"))
        assert.is_nil(types.group_outline("essay"))
    end)
end)

describe("types.multi_idea_paragraph", function()
    it("is true only for summary, which condenses a whole group", function()
        for _, id in ipairs(types.names()) do
            assert.equals(id == "summary", types.multi_idea_paragraph(id))
        end
    end)
end)

describe("archetypes per type", function()
    it("gives fiction a cast and a chronology, an essay its sources", function()
        local function ids(type_name)
            local out = {}
            for _, kind in ipairs(types.section_kinds(type_name)) do out[#out + 1] = kind.id end
            return out
        end
        assert.same({ "prose", "characters", "setting", "chronology", "turning_points", "themes" },
            ids("novel"))
        assert.same({ "prose", "key_concepts", "sources", "counterarguments", "themes" },
            ids("essay"))
        assert.same({ "prose", "key_concepts", "sources" }, ids("summary"))
    end)

    it("treats prose and an unknown id alike: guided by the type alone", function()
        assert.is_nil(types.section_kind("novel", "prose"))
        assert.is_nil(types.section_kind("novel", "nonsense"))
        assert.is_nil(types.section_kind("novel", nil))
        assert.is_nil(types.section_kind("novel", ""))
    end)

    it("finds an archetype the type actually offers", function()
        local kind = types.section_kind("novel", "characters")
        assert.is_not_nil(kind)
        assert.equals("characters", kind.id)
    end)

    it("does not find one the type does not offer", function()
        assert.is_nil(types.section_kind("summary", "chronology"))
    end)
end)

describe("guides fall through from the archetype to the type", function()
    it("uses the archetype's question when it has one", function()
        local kind = types.section_kind("novel", "characters")
        assert.equals(kind.idea_prompt.en, types.idea_prompt("novel", "en", false, "characters"))
    end)

    it("uses the type's question for a plain prose section", function()
        assert.equals(types.configs.novel.idea_prompt.en,
            types.idea_prompt("novel", "en", false, "prose"))
    end)

    it("swaps in the subsection question inside a section", function()
        assert.equals(types.configs.novel.subsection_idea_prompt.es,
            types.idea_prompt("novel", "es", true, nil))
    end)
end)
