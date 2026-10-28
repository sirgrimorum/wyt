-- The state of a project, read from disk and from its git history: where the
-- writer last stopped, and what is still open. `:WYTToday` builds its brief from
-- this. Nothing here calls the LLM.
local M = {}

--- The lines of a file's `content`. A file saved with `fileformat=dos` reaches
--- disk with CRLF, and the `\r` left on each line made a title read "Port\r"
--- and a placeholder stop matching at its `]*$`.
function M.lines(content)
    return vim.split((content or ""):gsub("\r\n", "\n"), "\n", { plain = true })
end

--- Whether each of `lines` sits inside a fence tagged `old`, where
--- re-implementing a group parks the text of groups the plan dropped. The
--- export leaves those out, so nothing there is open or a place to write. The
--- fences are written back to back: "``````old" closes one and opens the next.
function M.parked(lines)
    local out, in_old = {}, false
    for i, line in ipairs(lines) do
        if in_old then
            out[i] = true
            if line:match("^```") then in_old = line:match("^```.*```old") ~= nil end
        else
            in_old = line:match("^```old") ~= nil
            out[i] = in_old
        end
    end
    return out
end

--- The pattern of a `## Group: <name>` line in a text.wyt.md; captures the name.
function M.group_marker(project_mod)
    return "^##%s+" .. vim.pesc(project_mod.t("group_tag")) .. ":%s*(.+)$"
end

--- True when the section at `dir` holds sub-sections (`sections: true`): its
--- groups are folders, and a text.wyt.md left there is never exported.
function M.nested(project_mod, dir)
    return project_mod.config_value(project_mod.read_file(dir .. "config.wyt.yml"), "sections") == "true"
end

--- The freewrites waiting in the project, newest first (named by date and
--- time, so the name sorts them), and the folder they are in.
function M.freewrites(project_mod)
    local dir = project_mod.project_root .. "freewrite/"
    local files = vim.fn.isdirectory(dir) == 1 and vim.fn.readdir(dir, function(n) return n:match("%.md$") and 1 or 0 end) or {}
    table.sort(files, function(a, b) return a > b end)
    return files, dir
end

--- Placeholders still waiting in `lines`, as { line = n, idea = "..." }.
function M.placeholders(project_mod, lines)
    local pat = require("wyt.text").placeholder_pattern(project_mod)
    local parked = M.parked(lines)
    local found = {}
    for i, line in ipairs(lines) do
        local idea = not parked[i] and line:match(pat)
        if idea then found[#found + 1] = { line = i, idea = idea } end
    end
    return found
end

--- What a plan still leaves open: ideas under `## Ideas` that no group claimed,
--- and groups never implemented or edited since. An edited group counts: its
--- text no longer matches what the plan says.
function M.plan_gaps(project_mod, plan_content)
    plan_content = plan_content or ""
    local gaps = { ungrouped = 0, pending_groups = {} }

    local header = "## " .. project_mod.t("ideas_section")
    local start = plan_content:find(header, 1, true)
    if start then
        local rest = plan_content:sub(start + #header)
        local block = rest:match("^(.-)\n## ") or rest
        local tag = "[" .. project_mod.t("group_tag") .. ": "
        for line in block:gmatch("[^\n]+") do
            if line:match("^%- ") and not line:find(tag, 1, true) then
                gaps.ungrouped = gaps.ungrouped + 1
            end
        end
    end

    local done = "[" .. project_mod.t("implemented") .. "]"
    local marker = "## " .. project_mod.t("group_tag") .. ": "
    for line in plan_content:gmatch("[^\n]+") do
        if line:sub(1, #marker) == marker and not line:find(done, 1, true) then
            -- Parenthesised: clean_group_name is a gsub and returns its count too.
            table.insert(gaps.pending_groups, (project_mod.clean_group_name(line:sub(#marker + 1))))
        end
    end
    return gaps
end

--- Every section in plan order, the root first: the same walk the export and
--- `:WYTNav` make, so a folder no plan names is not part of it. Each entry is
--- { dir, title, definition, placeholders, ungrouped, pending_groups }.
function M.sections(project_mod)
    local out = {}
    local function walk(dir, level)
        local plan_content = project_mod.read_file(dir .. "plan.wyt.md") or ""
        local gaps = M.plan_gaps(project_mod, plan_content)
        local text = project_mod.read_file(dir .. "text.wyt.md")
        out[#out + 1] = {
            dir = dir,
            title = plan_content:match("^#%s+([^\r\n]+)") or "",
            definition = level > 1 and project_mod.is_definition_section(dir),
            placeholders = text and M.placeholders(project_mod, M.lines(text)) or {},
            ungrouped = gaps.ungrouped,
            pending_groups = gaps.pending_groups,
        }
        for _, name in ipairs(project_mod.get_groups(plan_content)) do
            local sub = project_mod.group_dir(dir, name)
            if sub then walk(sub, level + 1) end
        end
    end
    walk(project_mod.project_root, 1)
    return out
end

local function git(root, args)
    local cmd = { "git", "-C", root }
    vim.list_extend(cmd, args)
    local out = vim.fn.system(cmd)
    if vim.v.shell_error ~= 0 then return nil end
    return out
end

--- Where the writer last wrote prose: the `text.wyt.md` of the newest commit
--- that touched one, the last line its last hunk changed, and the commit time.
--- Every save commits, so this is the end of the last session. nil when no text
--- has been committed yet.
--- Returns { path, line, time }.
function M.last_edit(root)
    -- A plan or a config save is not where the writing stopped, so only text
    -- files count. `*` crosses `/` in a pathspec, which reaches every section.
    -- And only the writer's own saves: every WYT commit is `git add .`, so an
    -- "Implement group" commit carries the placeholders it wrote into the text
    -- and read as a session that never happened. `--relative`: a project kept
    -- inside a larger repository still gets paths from its own root.
    local log = git(root, { "log", "-1", "--no-color", "--relative", "--grep=^Save: ", "--format=%H %at", "--name-only", "--", "*text.wyt.md" })
    if not log or log == "" then return nil end
    local sha, time = log:match("^(%x+) (%d+)")
    if not sha then return nil end
    local file = log:match("\n([^\n]*text%.wyt%.md)")
    if not file then return nil end

    local diff = git(root, { "show", "--no-color", "--format=", "-U0", sha, "--", file }) or ""
    local line = 1
    for start, count in diff:gmatch("\n@@ %-%d+,?%d* %+(%d+),?(%d*) @@") do
        start, count = tonumber(start), tonumber(count ~= "" and count or "1")
        -- A pure deletion has no new lines and points just before them.
        line = count == 0 and math.max(start, 1) or start + count - 1
    end
    return { path = root .. file, line = line, time = tonumber(time) }
end

-- A line that is prose the writer wrote: not blank, not WYT's group marker, not
-- a placeholder still waiting for its paragraph.
local function is_prose(project_mod, line, pat)
    if line:match("^%s*$") then return false end
    if line:match("^##%s+" .. vim.pesc(project_mod.t("group_tag")) .. ":") then return false end
    return line:match(pat) == nil
end

--- The paragraph around `line_nr` in `lines`, or the nearest written one before
--- it when that line is blank, a marker or a placeholder: the end of the last
--- session often lands on the blank line after the paragraph just finished.
--- Returns the text and the paragraph's last line, or nil when nothing is
--- written up to there.
function M.paragraph_at(project_mod, lines, line_nr)
    local pat = require("wyt.text").placeholder_pattern(project_mod)
    local i = math.min(line_nr, #lines)
    while i >= 1 and not is_prose(project_mod, lines[i], pat) do i = i - 1 end
    if i < 1 then
        -- Nothing above: the first paragraph after it, if the session wrote one.
        i = line_nr
        while i <= #lines and not is_prose(project_mod, lines[i], pat) do i = i + 1 end
        if i > #lines then return nil end
    end
    local first, last = i, i
    while first > 1 and is_prose(project_mod, lines[first - 1], pat) do first = first - 1 end
    while last < #lines and is_prose(project_mod, lines[last + 1], pat) do last = last + 1 end
    return table.concat(lines, "\n", first, last), last
end

--- The scene around `line_nr`: the written lines of the `## Group:` block that
--- holds it, and that group's name (nil before the first marker).
function M.scene_at(project_mod, lines, line_nr)
    local marker = M.group_marker(project_mod)
    local first, name = 1, nil
    for i = math.min(line_nr, #lines), 1, -1 do
        local m = lines[i]:match(marker)
        if m then first, name = i + 1, project_mod.clean_group_name(m); break end
    end
    local last = #lines
    for i = first, #lines do
        if lines[i]:match(marker) then last = i - 1; break end
    end
    return M.prose_of(project_mod, vim.list_slice(lines, first, last)), name
end

--- The written text of `lines`, markers and placeholders left out.
function M.prose_of(project_mod, lines)
    local pat = require("wyt.text").placeholder_pattern(project_mod)
    local kept = {}
    for _, line in ipairs(lines) do
        if line:match("^%s*$") or is_prose(project_mod, line, pat) then kept[#kept + 1] = line end
    end
    return vim.trim((table.concat(kept, "\n"):gsub("\n\n\n+", "\n\n")))
end

return M
