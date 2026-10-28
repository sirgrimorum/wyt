-- :WYTToday, the way back into a project: a recap sized by how long the writer
-- has been away, what is still open, one prompt, and a menu of where to start.
-- Rereading to find the thread used to eat the writing time, so the brief
-- carries the last paragraph word for word and a summary only past a day.
local M = {}

local DAY = 24 * 3600
-- More than two placeholders turns a choice of where to start into a list to read.
local MAX_FILL = 2

--- How much the recap brings back after `seconds` away: the last paragraph
--- only, that plus a summary of its scene, or that plus its whole chapter.
function M.recap_depth(seconds)
    if seconds < DAY then return "paragraph" end
    if seconds < 7 * DAY then return "scene" end
    return "chapter"
end

--- `seconds` as the brief says it: "12 min ago", "yesterday", "9 days ago".
function M.ago(seconds, t)
    if seconds < 3600 then return t("ago_minutes"):format(math.max(1, math.floor(seconds / 60))) end
    if seconds < DAY then return t("ago_hours"):format(math.floor(seconds / 3600)) end
    local days = math.floor(seconds / DAY)
    if days == 1 then return t("ago_yesterday") end
    return t("ago_days"):format(days)
end

--- One line of what is still open across the content sections, or nil.
--- Reference sections are left out: an unexpanded character sheet is not
--- something the writer came to write today. Their wyt markers still count:
--- a gap left in the notes is one the writer chose to come back to.
function M.open_summary(sections, t)
    local placeholders, groups, ideas, marks = 0, 0, 0, 0
    for _, s in ipairs(sections) do
        if not s.definition then
            placeholders = placeholders + #s.placeholders
            groups = groups + #s.pending_groups
            ideas = ideas + s.ungrouped
        end
        marks = marks + #s.markers
    end
    local parts = {}
    if placeholders > 0 then parts[#parts + 1] = t("today_open_placeholders"):format(placeholders) end
    if groups > 0 then parts[#parts + 1] = t("today_open_groups"):format(groups) end
    if ideas > 0 then parts[#parts + 1] = t("today_open_ideas"):format(ideas) end
    if marks > 0 then parts[#parts + 1] = t("today_open_markers"):format(marks) end
    if #parts == 0 then return nil end
    return table.concat(parts, ", ")
end

--- The brief as the panel shows it. `b` is { where, ago, paragraph, summary,
--- open, prompt }; every field may be missing.
function M.compose(b, t)
    local parts = {}
    if b.paragraph then
        parts[#parts + 1] = t("today_last_time"):format(b.ago, b.where)
        parts[#parts + 1] = b.paragraph
    else
        parts[#parts + 1] = t("today_nothing_yet")
    end
    if b.summary then parts[#parts + 1] = t("today_so_far") .. b.summary end
    if b.open then parts[#parts + 1] = t("today_open") .. b.open end
    if b.prompt then parts[#parts + 1] = t("today_prompt_line") .. b.prompt end
    return table.concat(parts, "\n\n")
end

local function norm(p) return (p:gsub("\\", "/")) end

--- The menu, in order: continue where the last session stopped, a couple of
--- open placeholders, and free writing. Placeholders after the last edit in the
--- same file come first, since that is the text the writer was moving through.
--- Each item is { label, path, line } or { label, freewrite = true }.
function M.options(edit, where, sections, prompt, t)
    local items = {}
    if edit then
        items[#items + 1] = { label = t("today_continue"):format(where), path = edit.path, line = edit.line_end }
    end

    local ahead, rest = {}, {}
    for _, s in ipairs(sections) do
        if not s.definition then
            local path = s.dir .. "text.wyt.md"
            local here = edit and norm(path) == norm(edit.path)
            for _, ph in ipairs(s.placeholders) do
                local entry = { path = path, line = ph.line, idea = ph.idea }
                table.insert((here and ph.line > edit.line) and ahead or rest, entry)
            end
        end
    end
    vim.list_extend(ahead, rest)
    local ui = require("wyt.ui")
    for i = 1, math.min(MAX_FILL, #ahead) do
        local ph = ahead[i]
        items[#items + 1] = { label = t("today_fill"):format(ui.truncate(ph.idea, 40)), path = ph.path, line = ph.line }
    end

    items[#items + 1] = { label = prompt and t("today_freewrite_prompt") or t("today_freewrite"), freewrite = true }
    return items
end

function M.open()
    local project = require("wyt.project")
    if not project.setup() then return end
    local ui = require("wyt.ui")
    local status = require("wyt.status")
    -- The recap reads the last commit, and a save is what makes one.
    ui.save_current()
    local t = project.t

    local sections = status.sections(project)
    local edit = status.last_edit(project.project_root)
    local brief = { open = M.open_summary(sections, t) }
    local depth, text = "paragraph", nil

    local content = edit and project.read_file(edit.path)
    if content then
        local lines = status.lines(content)
        brief.paragraph, edit.line_end = status.paragraph_at(project, lines, edit.line)
        if brief.paragraph then
            local away = os.time() - edit.time
            brief.ago = M.ago(away, t)
            depth = M.recap_depth(away)
            local scene, scene_name = status.scene_at(project, lines, edit.line)
            local dir = edit.path:match("^(.*[\\/])")
            local title = (project.read_file(dir .. "plan.wyt.md") or ""):match("^#%s+([^\r\n]+)") or ""
            brief.where = scene_name and (title .. " › " .. scene_name) or title
            -- The chapter is the whole text file the session was in.
            text = depth == "chapter" and status.prose_of(project, lines) or scene
        end
    end
    -- A commit whose text has since been deleted leaves nothing to continue.
    if not brief.paragraph then edit = nil end

    local function show(ai)
        brief.summary = ai and ai.summary
        brief.prompt = ai and ai.prompt
        -- The picker hands back the label alone, so two placeholders with the
        -- same idea cannot both be offered: the first, nearer the last edit, stays.
        local labels, by_label = {}, {}
        for _, item in ipairs(M.options(edit, brief.where, sections, brief.prompt, t)) do
            if not by_label[item.label] then
                labels[#labels + 1] = item.label
                by_label[item.label] = item
            end
        end
        ui.ask_select({
            title = t("today_title"),
            question = M.compose(brief, t),
            prompt = t("today_menu"),
        }, labels, function(choice)
            local item = choice and by_label[choice]
            if not item then return end
            if item.freewrite then return require("wyt.freewrite").open(brief.prompt) end
            ui.edit_file(item.path)
            local last = vim.api.nvim_buf_line_count(0)
            vim.api.nvim_win_set_cursor(0, { math.min(item.line, last), 0 })
        end)
    end

    vim.notify(t("today_generating"), vim.log.levels.INFO)
    require("wyt.llm").today({
        lang = project.lang,
        project = project.description_context(project.read_file(project.plan_path) or ""),
        ago = brief.ago,
        depth = depth,
        text = text,
        last_paragraph = brief.paragraph,
        open = brief.open,
    }, function(ai, err)
        -- Without a key or a connection the brief still has everything that
        -- came from disk; only the summary and the prompt are missing.
        if err then vim.notify(t("today_no_ai") .. err, vim.log.levels.WARN) end
        show(ai)
    end)
end

return M
