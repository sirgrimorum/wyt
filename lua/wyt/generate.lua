-- :WYTGenerate. What the writer wants generated depends on where they are:
-- between two paragraphs of `text.wyt.md` they want a bridge between them, under
-- a group of `plan.wyt.md` they want more ideas for that group. The cursor is
-- the whole instruction in the first case and the subject in the second, so it
-- is read as context and not merely used as an insertion point.
local api = vim.api
local loc = require("wyt.localization")

local M = {}

-- The insertion point is held as an extmark while the request is out.
local NS = api.nvim_create_namespace("wyt_generate")

local MAX_CONTEXT = 600
local MAX_IDEAS = 5

--- `tail` keeps the end of the text rather than its start. The paragraph
--- before the cursor is read backwards: its last sentences are the ones the
--- new prose has to follow, and a long one used to arrive with them cut off.
--- The cut counts characters, not bytes: a slice through an accent would hand
--- the API a broken UTF-8 sequence.
local function clip(text, tail)
    text = vim.trim((text:gsub("%s+", " ")))
    local len = vim.fn.strchars(text)
    if len <= MAX_CONTEXT then return text end
    if tail then return vim.fn.strcharpart(text, len - MAX_CONTEXT) end
    return vim.fn.strcharpart(text, 0, MAX_CONTEXT)
end

--- The nearest heading above `row`, with the group marker and any status tag
--- stripped: the name of the section or group the cursor is working inside.
local function heading_above(lines, row, project)
    local marker = project.t("group_tag") .. ": "
    for i = row, 1, -1 do
        local title = lines[i] and lines[i]:match("^#+%s+(.+)$")
        if title then
            if title:sub(1, #marker) == marker then title = title:sub(#marker + 1) end
            return project.clean_group_name(title), i
        end
    end
    return nil, nil
end

--- The block of prose immediately before `row`, skipping the blank lines that
--- separate it. Returns nil when there is nothing above but structure.
local function block_before(lines, row)
    local i = row
    while i >= 1 and lines[i]:match("^%s*$") do i = i - 1 end
    local collected = {}
    while i >= 1 and not lines[i]:match("^%s*$") and not lines[i]:match("^#") do
        table.insert(collected, 1, lines[i])
        i = i - 1
    end
    if #collected == 0 then return nil end
    return clip(table.concat(collected, " "), true)
end

local function block_after(lines, row)
    local i = row
    while i <= #lines and lines[i]:match("^%s*$") do i = i + 1 end
    local collected = {}
    while i <= #lines and not lines[i]:match("^%s*$") and not lines[i]:match("^#") do
        table.insert(collected, lines[i])
        i = i + 1
    end
    if #collected == 0 then return nil end
    return clip(table.concat(collected, " "))
end

--- The ideas already listed under the heading the cursor is in, so a
--- brainstorm adds to them instead of repeating them back.
local function siblings_under(lines, heading_row)
    if not heading_row then return nil end
    local found = {}
    for i = heading_row + 1, #lines do
        if lines[i]:match("^#") then break end
        local idea = lines[i]:match("^%s*%-%s+(.+)$")
        if idea then found[#found + 1] = vim.trim(idea) end
    end
    if #found == 0 then return nil end
    return clip(table.concat(found, "; "))
end

--- Everything the model is told about where the cursor is.
--- `mode` is "plan" when ideas are wanted, "text" when prose is, "free"
--- outside a WYT file, which reads its surroundings the same way as text.
function M.context(buf, row)
    local project = require("wyt.project")
    local name = api.nvim_buf_get_name(buf)
    local lines = api.nvim_buf_get_lines(buf, 0, -1, false)

    local mode = "free"
    if name:match("plan%.wyt%.md$") then
        mode = "plan"
    elseif name:match("text%.wyt%.md$") then
        mode = "text"
    end

    local heading, heading_row = heading_above(lines, row, project)
    local plan_content = project.read_file(project.section_plan_path) or ""
    local ctx = {
        mode = mode,
        lang = project.lang,
        project = project.description_context(plan_content),
        -- What the type wants a paragraph to be. Ignored in plan mode, where
        -- ideas are asked for instead of prose.
        prose_kind = require("wyt.types").prose_kind(project.get_project_type(), project.lang),
        heading = heading,
        max_ideas = MAX_IDEAS,
    }
    if mode == "plan" then
        ctx.existing = siblings_under(lines, heading_row)
    else
        ctx.before = block_before(lines, row)
        ctx.after = block_after(lines, row + 1)
    end
    return ctx
end

-- Ideas go into the plan as list items, whatever shape the model replied in.
local function as_ideas(text)
    local llm = require("wyt.llm")
    local ideas = {}
    for _, line in ipairs(vim.split(text, "\n", { plain = true })) do
        -- Judged on the raw line: to_single_line strips a heading's hashes, and
        -- one line alone gives it no second line to skip a preamble for.
        -- `#silence` with no space is a hashtag, and stays an idea.
        local structure = line:match("^%s*#+%s") or vim.trim(line):match(":$")
        local idea = structure and "" or llm.to_single_line(line)
        if idea ~= "" then
            ideas[#ideas + 1] = "- " .. idea
        end
        if #ideas == MAX_IDEAS then break end
    end
    return ideas
end

--- Generate at the cursor and insert the result in the shape the file expects.
function M.run(instruction)
    local project = require("wyt.project")
    local llm = require("wyt.llm")
    if not project.setup() then return end

    local buf = api.nvim_get_current_buf()
    local row = api.nvim_win_get_cursor(0)[1]
    local ctx = M.context(buf, row)
    ctx.instruction = instruction and vim.trim(instruction) or ""

    -- The reply lands seconds later and the writer keeps typing meanwhile. An
    -- extmark moves with their edits, so the prose still arrives where the
    -- cursor was instead of at a line number that has since become someone
    -- else's paragraph.
    local mark = api.nvim_buf_set_extmark(buf, NS, row - 1, 0, {})

    vim.notify(loc.t("llm_generating"), vim.log.levels.INFO)
    llm.generate_in_context(ctx, function(result, err)
        local pos = api.nvim_buf_is_loaded(buf)
            and api.nvim_buf_get_extmark_by_id(buf, NS, mark, {}) or {}
        if pos[1] then api.nvim_buf_del_extmark(buf, NS, mark) end
        if err or not result or result == "" then
            vim.notify(loc.t("llm_error") .. (err or ""), vim.log.levels.WARN)
            return
        end
        if not pos[1] then
            vim.notify(loc.t("llm_buffer_gone"), vim.log.levels.WARN)
            return
        end
        row = pos[1] + 1
        local inserted
        if ctx.mode == "plan" then
            -- A paragraph dropped into a plan would not be an idea, and the
            -- sync would carry the wreckage into every group.
            inserted = as_ideas(result)
            if #inserted == 0 then
                vim.notify(loc.t("llm_unusable_reply"), vim.log.levels.WARN)
                return
            end
            api.nvim_buf_set_lines(buf, row, row, false, inserted)
            vim.notify(string.format(loc.t("ideas_inserted"), #inserted), vim.log.levels.INFO)
        else
            inserted = vim.split(llm.to_prose(result), "\n", { plain = true })
            -- Markdown joins lines that touch, so a paragraph dropped against
            -- its neighbour would merge into it in the export.
            local around = api.nvim_buf_get_lines(buf, row - 1, row + 1, false)
            local function blank(l) return l == nil or l:match("^%s*$") ~= nil end
            if not blank(around[1]) then table.insert(inserted, 1, "") end
            if around[2] and not blank(around[2]) then table.insert(inserted, "") end
            api.nvim_buf_set_lines(buf, row, row, false, inserted)
            vim.notify(loc.t("text_inserted"), vim.log.levels.INFO)
        end
    end)
end

return M
