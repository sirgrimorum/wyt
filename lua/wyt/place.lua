-- Place: freewrite paragraphs moved to where they belong in the project, one
-- chunk at a time, each confirmed by the writer. The model only splits, points
-- and names; the words are moved, never rewritten, so what lands in a text is
-- what was typed.
local M = {}

local status = require("wyt.status")

--- The paragraphs of a freewrite file, and apart from them the prompt quote
--- on its first line, which `freewrite.open` writes and Place writes back.
function M.paragraphs(content)
    local lines = status.lines(content)
    local header = (lines[1] or ""):match("^> ") and table.remove(lines, 1) or nil
    local out, cur = {}, {}
    local function flush()
        if #cur > 0 then out[#out + 1] = table.concat(cur, "\n") end
        cur = {}
    end
    for _, line in ipairs(lines) do
        if line:match("^%s*$") then flush() else cur[#cur + 1] = line end
    end
    flush()
    return out, header
end

--- Every home a chunk can go to, in plan order: the end of a group's text, a
--- new idea at the end of it, a placeholder still waiting for its paragraph, a
--- new group, or the ideas of a section's plan. Each is { id, kind, label, dir,
--- path, key }; a new group also carries `nested`, its section's `sections:`.
function M.targets(project_mod)
    local t = project_mod.t
    local out = {}
    local function add(target)
        target.id = "T" .. (#out + 1)
        out[#out + 1] = target
    end
    local marker = status.group_marker(project_mod)
    for _, s in ipairs(status.sections(project_mod)) do
        local text_path = s.dir .. "text.wyt.md"
        -- A level that holds sub-sections exports only them: a text.wyt.md
        -- left there is never read, so nothing placed in it would show.
        local nested = status.nested(project_mod, s.dir)
        local lines = nested and {} or status.lines(project_mod.read_file(text_path))
        local parked = status.parked(lines)
        for i, line in ipairs(lines) do
            local group = not parked[i] and line:match(marker)
            if group then
                group = project_mod.clean_group_name(group)
                local where = s.title .. " › " .. group
                add({ kind = "after", label = t("place_after"):format(where), dir = s.dir, path = text_path, key = group })
                add({ kind = "new_idea", label = t("place_new_idea"):format(where), dir = s.dir, path = text_path, key = group })
            end
        end
        for _, p in ipairs(nested and {} or s.placeholders) do
            add({ kind = "placeholder", label = t("place_fill"):format(p.idea) .. " (" .. s.title .. ")",
                dir = s.dir, path = text_path, key = p.idea })
        end
        add({ kind = "new_group", label = t("place_new_group"):format(s.title), dir = s.dir, path = text_path, nested = nested })
        add({ kind = "idea", label = t("place_idea"):format(s.title), dir = s.dir, path = s.dir .. "plan.wyt.md" })
    end
    return out
end

--- The model's chunks, kept only where they make sense: a known target, the
--- names a new idea or group needs, and paragraphs among `allowed` that no
--- earlier chunk took. Ordered by their first paragraph, so the menu walks the
--- freewrite top to bottom.
function M.chunks(raw, allowed, by_id)
    local free = {}
    for _, n in ipairs(allowed) do free[n] = true end
    local out = {}
    for _, c in ipairs(raw) do
        local target = by_id[c.target]
        local kind = target and target.kind
        local named = (kind ~= "new_idea" or c.idea) and (kind ~= "new_group" or (c.group and c.idea))
        if (target or c.target == "keep") and named then
            local paragraphs = {}
            for _, n in ipairs(c.paragraphs) do
                n = tonumber(n)
                if n and free[n] then
                    free[n] = nil
                    paragraphs[#paragraphs + 1] = n
                end
            end
            table.sort(paragraphs)
            if #paragraphs > 0 then
                out[#out + 1] = { paragraphs = paragraphs, target = target, why = c.why, idea = c.idea, group = c.group }
            end
        end
    end
    -- What the model left out is still the writer's to decide, so it comes back
    -- as kept. A reply with nothing usable stays empty: it is no proposal.
    if #out > 0 then
        local rest = {}
        for _, n in ipairs(allowed) do
            if free[n] then rest[#rest + 1] = n end
        end
        if #rest > 0 then out[#out + 1] = { paragraphs = rest } end
    end
    table.sort(out, function(a, b) return a.paragraphs[1] < b.paragraphs[1] end)
    return out
end

-- After the last paragraph written in `group`, ahead of the placeholders still
-- waiting: the freewrite continues the prose. Nil when the text has no such group.
local function after_group(project_mod, lines, group)
    local marker = status.group_marker(project_mod)
    local pat = require("wyt.text").placeholder_pattern(project_mod)
    local parked = status.parked(lines)
    local start, at
    for i, line in ipairs(lines) do
        local name = not parked[i] and line:match(marker)
        if start and (name or parked[i]) then break end
        if name and project_mod.clean_group_name(name) == group then
            start, at = i, i + 1
        elseif start and not line:match("^%s*$") and not line:match(pat) then
            at = i + 1
        end
    end
    return at
end

local function insert(lines, at, text)
    for j, line in ipairs(vim.split(text, "\n", { plain = true })) do table.insert(lines, at + j - 1, line) end
end

local function trimmed(content) return ((content or ""):gsub("%s+$", "")) end

-- Written with the line ending the file had, so a CRLF file does not show up
-- whole in the commit. False when the write failed: write_file has said so.
local function save(project_mod, path, content, like)
    if like and like:find("\r\n", 1, true) then content = content:gsub("\r?\n", "\r\n") end
    return project_mod.write_file(path, content)
end

-- The plan side of a new idea: tagged under Ideas, the way a group claims its
-- ideas, and listed under the group itself.
local function plan_with_idea(project_mod, plan, group, idea)
    local t = project_mod.t
    plan = require("wyt.plan").add_item_to_section(plan, t("ideas_section"),
        idea .. " [" .. t("group_tag") .. ": " .. group .. "]")
    local lines = status.lines(plan)
    local marker = status.group_marker(project_mod)
    local at
    for i, line in ipairs(lines) do
        local name = line:match(marker)
        if at and line:match("^## ") then break end
        if name and project_mod.clean_group_name(name) == group then
            at = i + 1
        elseif at and line:match("^%- ") then
            at = i + 1
        end
    end
    if at then table.insert(lines, at, "- " .. idea) end
    return table.concat(lines, "\n")
end

-- A new group: claimed in the plan as implemented, since its text is the chunk.
-- In a section that holds sub-sections it is a section of its own, built as
-- implementing the group would, its one idea its one group. Place does not stop
-- to ask its archetype: reference material passes its own down, as everywhere,
-- and anything else is prose.
local function new_group(project_mod, c, text, plan, plan_path, raw_plan)
    local t, target = project_mod.t, c.target
    for _, name in ipairs(project_mod.get_groups(plan)) do
        if name == c.group then return nil, "place_taken" end
    end
    local block = "## " .. t("group_tag") .. ": "
    local text_path = target.path
    if target.nested then
        local slug = project_mod.slugify(c.group)
        local dir = target.dir .. slug .. "/"
        if slug == "" or vim.fn.isdirectory(dir) == 1 then return nil, "place_taken" end
        vim.fn.mkdir(dir, "p")
        local definition = project_mod.is_definition_section(target.dir)
        project_mod.write_file(dir .. "config.wyt.yml", string.format(
            "type: %s\nsection_kind: %s\ncontent_type: %s\nsections: false\n",
            project_mod.get_project_type(),
            definition and project_mod.section_kind_of(target.dir) or "prose",
            definition and "definition" or "content"))
        project_mod.write_file(dir .. "plan.wyt.md", table.concat({
            "# " .. c.group, "", "## " .. t("ideas_section"), "",
            "- " .. c.idea .. " [" .. t("group_tag") .. ": " .. c.idea .. "]", "",
            block .. c.idea .. " [" .. t("implemented") .. "]", "- " .. c.idea, "",
        }, "\n"))
        text_path = dir .. "text.wyt.md"
        if not project_mod.write_file(text_path, block .. c.idea .. "\n\n" .. text .. "\n") then return nil end
    else
        local raw = project_mod.read_file(text_path)
        local current = trimmed(raw):gsub("\r\n", "\n")
        if not save(project_mod, text_path, (current == "" and "" or current .. "\n\n")
            .. block .. c.group .. "\n\n" .. text .. "\n", raw) then return nil end
    end
    plan = require("wyt.plan").add_item_to_section(plan, t("ideas_section"),
        c.idea .. " [" .. t("group_tag") .. ": " .. c.group .. "]")
    save(project_mod, plan_path, trimmed(plan) .. "\n\n" .. block .. c.group
        .. " [" .. t("implemented") .. "]\n- " .. c.idea .. "\n", raw_plan)
    return { text_path, plan_path }
end

--- Write chunk `c`'s `text` into its target. Returns the files written, the
--- first one the place to show; or nil and the key of why it could not: a
--- placeholder an earlier chunk of this run already filled, or a new group
--- whose name is taken. Nil alone when the chunk's own words failed to write;
--- a plan that fails after them leaves the words placed, the part that cannot
--- be lost.
function M.apply(project_mod, c, text)
    local target = c.target
    local plan_path = target.dir .. "plan.wyt.md"
    -- A plan saved with CRLF named every group "X [Implemented]\r", and a
    -- taken name went unnoticed.
    local raw_plan = project_mod.read_file(plan_path)
    local plan = ((raw_plan or ""):gsub("\r\n", "\n"))
    if target.kind == "idea" then
        -- An idea is one line in the plan.
        local item = (text:gsub("%s*\n%s*", " "))
        local ok = save(project_mod, plan_path,
            require("wyt.plan").add_item_to_section(plan, project_mod.t("ideas_section"), item), raw_plan)
        return ok and { plan_path } or nil
    end
    if target.kind == "new_group" then return new_group(project_mod, c, text, plan, plan_path, raw_plan) end

    local raw = project_mod.read_file(target.path)
    local lines = status.lines(raw)
    local at
    if target.kind == "placeholder" then
        local pat = require("wyt.text").placeholder_pattern(project_mod)
        local parked = status.parked(lines)
        for i, line in ipairs(lines) do
            if not parked[i] and line:match(pat) == target.key then
                at = i
                table.remove(lines, i)
                break
            end
        end
        if not at then return nil, "place_gone" end
        insert(lines, at, text)
    else
        at = after_group(project_mod, lines, target.key)
        if not at then return nil, "place_gone" end
        insert(lines, at, "\n" .. text)
    end
    if not save(project_mod, target.path, table.concat(lines, "\n"), raw) then return nil end
    if target.kind ~= "new_idea" then return { target.path } end
    save(project_mod, plan_path, plan_with_idea(project_mod, plan, target.key, c.idea), raw_plan)
    return { target.path, plan_path }
end

-- The loaded buffer of `path`, or nil. Not bufnr(), which reads its argument
-- as a pattern; names compare the way ui.canonical has Windows compare them.
local function buffer_of(path)
    local want = require("wyt.ui").canonical(path)
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
        local name = vim.api.nvim_buf_get_name(b)
        if vim.api.nvim_buf_is_loaded(b) and name ~= "" and require("wyt.ui").canonical(name) == want then return b end
    end
end

-- Files written while their buffers sat loaded: reread them, or the next save
-- of a stale buffer writes the placed text back out. A buffer with edits made
-- during the run is left alone rather than thrown away: Neovim asks before
-- saving it over the file that changed.
local function reload(paths)
    for path in pairs(paths) do
        local b = buffer_of(path)
        if b and not vim.bo[b].modified then
            vim.api.nvim_buf_call(b, function() vim.cmd("silent edit!") end)
        end
    end
end

--- Where chunk `c` would go, as the menu says it.
local function where(t, c)
    if not c.target then return t("place_keep") end
    if c.target.kind == "new_idea" then return c.target.label .. ": " .. c.idea end
    if c.target.kind == "new_group" then return c.target.label .. ": " .. c.group .. " › " .. c.idea end
    return c.target.label
end

--- Run Place on the freewrite at `path`.
function M.run(path)
    local project = require("wyt.project")
    local ui = require("wyt.ui")
    local llm = require("wyt.llm")
    local t = project.t

    local content = project.read_file(path) or ""
    local paragraphs, header = M.paragraphs(content)
    if #paragraphs == 0 then return vim.notify(t("place_empty"), vim.log.levels.INFO) end
    local targets = M.targets(project)
    local by_id = {}
    for _, target in ipairs(targets) do by_id[target.id] = target end

    -- Read-only for the run: the paragraphs were read once, and what is typed
    -- in the freewrite meanwhile would be overwritten at the end, or saved back
    -- over a freewrite the run deleted. Every way out of the run unlocks it.
    local fw_buf = buffer_of(path)
    local was = fw_buf and vim.bo[fw_buf].modifiable
    local function unlock()
        if fw_buf and vim.api.nvim_buf_is_valid(fw_buf) then vim.bo[fw_buf].modifiable = was end
    end
    if fw_buf then vim.bo[fw_buf].modifiable = false end

    local function propose(numbers, change, callback)
        local list = {}
        for _, n in ipairs(numbers) do list[#list + 1] = { n = n, text = paragraphs[n] } end
        vim.notify(t("place_reading"), vim.log.levels.INFO)
        llm.place({
            lang = project.lang,
            project = project.description_context(project.read_file(project.plan_path) or ""),
            paragraphs = list,
            targets = targets,
            change = change,
        }, function(raw, err)
            if not raw then
                vim.notify(t("llm_error") .. tostring(err), vim.log.levels.WARN)
                return callback(nil)
            end
            callback(M.chunks(raw, numbers, by_id))
        end)
    end

    local queue, placed, written, last_path = {}, {}, {}, nil

    local function finish()
        unlock()
        local count = vim.tbl_count(placed)
        if count == 0 then return vim.notify(t("place_nothing"), vim.log.levels.INFO) end
        local rest = {}
        for n, text in ipairs(paragraphs) do
            if not placed[n] then rest[#rest + 1] = text end
        end
        local removed = false
        if #rest == 0 then
            removed = os.remove(path) ~= nil
        else
            if header then table.insert(rest, 1, header) end
            project.write_file(path, table.concat(rest, "\n\n") .. "\n")
            written[path] = true
        end
        reload(written)
        ui.edit_file(last_path)
        if removed then
            local b = buffer_of(path)
            if b then vim.api.nvim_buf_delete(b, { force = true }) end
        end
        project.commit_changes("Save: placed freewrite/" .. vim.fn.fnamemodify(path, ":t"))
        require("wyt.outline").refresh()
        vim.notify(t("place_done"):format(count, #paragraphs), vim.log.levels.INFO)
    end

    local step
    step = function(i)
        local c = queue[i]
        if not c then return finish() end
        local text = {}
        for _, n in ipairs(c.paragraphs) do text[#text + 1] = paragraphs[n] end
        text = table.concat(text, "\n\n")
        local items = c.target and { t("place_it"), t("place_change"), t("place_leave") }
            or { t("place_leave"), t("place_change") }
        ui.ask_select({
            title = t("place_title") .. " " .. i .. "/" .. #queue,
            question = text .. "\n\n→ " .. where(t, c) .. (c.why and ("\n" .. c.why) or ""),
            prompt = t("place_menu"),
        }, items, function(choice)
            -- Esc stops the run; what was placed stays placed.
            if not choice then return finish() end
            if choice == t("place_leave") then return step(i + 1) end
            if choice == t("place_it") then
                local files, why = M.apply(project, c, text)
                if files then
                    for _, n in ipairs(c.paragraphs) do placed[n] = true end
                    for _, f in ipairs(files) do written[f] = true end
                    last_path = files[1]
                elseif why then
                    vim.notify(t(why), vim.log.levels.WARN)
                end
                return step(i + 1)
            end
            ui.ask_input({ title = t("place_change"), question = t("place_change_q") }, function(note)
                if note == nil then return finish() end
                if note == "" then return step(i) end
                propose(c.paragraphs, { previous = where(t, c), note = note }, function(chunks)
                    if chunks and #chunks > 0 then
                        table.remove(queue, i)
                        for j, chunk in ipairs(chunks) do table.insert(queue, i + j - 1, chunk) end
                    elseif chunks then
                        vim.notify(t("place_no_proposal"), vim.log.levels.WARN)
                    end
                    step(i)
                end)
            end)
        end)
    end

    propose(vim.fn.range(1, #paragraphs), nil, function(chunks)
        if chunks and #chunks == 0 then vim.notify(t("place_no_reply"), vim.log.levels.WARN) end
        if not chunks or #chunks == 0 then return unlock() end
        queue = chunks
        step(1)
    end)
end

--- `:WYTPlace`: the freewrite on screen, or a pick of the project's, newest first.
function M.open()
    local project = require("wyt.project")
    if not project.setup() then return end
    -- Place rewrites files on disk, and a buffer with unsaved text would
    -- either lose it or put the placed text back out on its next save. Only
    -- this project's: a buffer elsewhere is not Place's to write.
    local ui = require("wyt.ui")
    local root = ui.canonical(project.project_root)
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
        local name = vim.api.nvim_buf_get_name(b)
        if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].modified and vim.bo[b].buftype == "" and name ~= ""
            and vim.startswith(ui.canonical(name), root) then
            vim.api.nvim_buf_call(b, function() pcall(vim.cmd, "silent write") end)
        end
    end
    local current = vim.fn.expand("%:p")
    if require("wyt.freewrite").is_freewrite(current) then return M.run(current) end

    local files, dir = status.freewrites(project)
    if #files == 0 then return vim.notify(project.t("place_none"), vim.log.levels.INFO) end
    vim.ui.select(files, { prompt = project.t("place_pick") }, function(choice)
        if choice then M.run(dir .. choice) end
    end)
end

return M
