-- :WYTResolve, the wyt markers answered: one model call proposes what goes in
-- each gap left while writing, and the writer takes, changes or skips each
-- answer. Nothing is written until the run ends, and then in one commit.
local M = {}

local status = require("wyt.status")
local markers = require("wyt.markers")

--- The texts to resolve, as { path, markers }: the text on screen when it has
--- markers, or every text in the project that has any. A level of sub-sections
--- has no text the export reads, so status.sections finds none there.
function M.files(project_mod)
    local ui = require("wyt.ui")
    local current = vim.fn.expand("%:p")
    current = current ~= "" and ui.canonical(current)
    local out = {}
    for _, s in ipairs(status.sections(project_mod)) do
        if #s.markers > 0 then
            local file = { path = s.dir .. "text.wyt.md", markers = s.markers }
            if current and ui.canonical(file.path) == current then return { file } end
            out[#out + 1] = file
        end
    end
    return out
end

--- `lines` with the accepted `items` written in: { m, answer }. Bottom up and
--- right to left, so a column found before stays true for the markers still to
--- go. A marker whose line changed since it was read is left alone. Returns the
--- new lines and how many were written.
function M.apply(lines, items)
    table.sort(items, function(a, b)
        if a.m.line ~= b.m.line then return a.m.line > b.m.line end
        return a.m.s > b.m.s
    end)
    local done = 0
    for _, item in ipairs(items) do
        local m, line = item.m, lines[item.m.line]
        if line and line:sub(m.s, m.e) == m.raw then
            local new = markers.replace(line, m, item.answer)
            table.remove(lines, m.line)
            for j = #new, 1, -1 do table.insert(lines, m.line, new[j]) end
            done = done + 1
        end
    end
    return lines, done
end

--- Run Resolve over `files`, from M.files.
function M.run(files)
    local project = require("wyt.project")
    local ui = require("wyt.ui")
    local llm = require("wyt.llm")
    local t = project.t

    local queue = {}
    for _, f in ipairs(files) do
        local lines = status.lines(project.read_file(f.path) or "")
        for _, m in ipairs(f.markers) do
            queue[#queue + 1] = {
                id = "M" .. (#queue + 1), path = f.path, m = m, text = m.text,
                paragraph = status.paragraph_at(project, lines, m.line) or lines[m.line],
            }
        end
    end
    local base = {
        lang = project.lang,
        project = project.description_context(project.read_file(project.plan_path) or ""),
        reference = require("wyt.search").reference(project),
    }

    local function answer(items, change, callback)
        vim.notify(t("resolve_reading"), vim.log.levels.INFO)
        llm.resolve(vim.tbl_extend("force", base, { markers = items, change = change }), function(answers, err)
            if not answers then vim.notify(t("llm_error") .. tostring(err), vim.log.levels.WARN) end
            callback(answers)
        end)
    end

    local function finish()
        local by_path, order, accepted = {}, {}, 0
        for _, item in ipairs(queue) do
            if item.accepted then
                if not by_path[item.path] then by_path[item.path], order[#order + 1] = {}, item.path end
                table.insert(by_path[item.path], item)
                accepted = accepted + 1
            end
        end
        if accepted == 0 then return vim.notify(t("resolve_nothing"), vim.log.levels.INFO) end
        local written, count = {}, 0
        for _, path in ipairs(order) do
            local raw = project.read_file(path) or ""
            local lines, done = M.apply(status.lines(raw), by_path[path])
            if done > 0 and project.write_file_like(path, table.concat(lines, "\n"), raw) then
                written[path], count = true, count + done
            end
        end
        if count < accepted then vim.notify(t("resolve_moved"):format(accepted - count), vim.log.levels.WARN) end
        if count == 0 then return end
        ui.reload(written)
        project.commit_changes("Save: resolved wyt markers")
        require("wyt.outline").refresh()
        vim.notify(t("resolve_done"):format(count, #queue), vim.log.levels.INFO)
    end

    local step
    step = function(i)
        local item = queue[i]
        if not item then return finish() end
        local items = item.answer and { t("resolve_use"), t("resolve_change"), t("resolve_skip") }
            or { t("resolve_skip"), t("resolve_change") }
        ui.ask_select({
            title = t("resolve_title") .. " " .. i .. "/" .. #queue,
            question = item.paragraph .. "\n\n" .. item.m.raw .. "\n→ " .. (item.answer or t("resolve_no_answer")),
            prompt = t("resolve_menu"),
        }, items, function(choice)
            -- Esc stops the run; what was taken is still written.
            if not choice then return finish() end
            if choice == t("resolve_skip") then return step(i + 1) end
            if choice == t("resolve_use") then
                item.accepted = true
                return step(i + 1)
            end
            ui.ask_input({ title = t("resolve_change"), question = t("resolve_change_q") }, function(note)
                if note == nil then return finish() end
                if note == "" then return step(i) end
                answer({ item }, { previous = item.answer, note = note }, function(answers)
                    if answers and answers[item.id] then
                        item.answer = answers[item.id]
                    elseif answers then
                        vim.notify(t("resolve_no_proposal"), vim.log.levels.WARN)
                    end
                    step(i)
                end)
            end)
        end)
    end

    answer(queue, nil, function(answers)
        if not answers then return end
        if vim.tbl_isempty(answers) then return vim.notify(t("resolve_no_reply"), vim.log.levels.WARN) end
        for _, item in ipairs(queue) do item.answer = answers[item.id] end
        step(1)
    end)
end

--- `:WYTResolve`: the markers of the text on screen, or of the whole project.
function M.open()
    local project = require("wyt.project")
    if not project.setup() then return end
    -- The markers are read from disk and the answers written there.
    require("wyt.ui").save_project(project.project_root)
    local files = M.files(project)
    if #files == 0 then return vim.notify(project.t("resolve_none"), vim.log.levels.INFO) end
    M.run(files)
end

return M
