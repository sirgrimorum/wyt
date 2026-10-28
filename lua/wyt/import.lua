-- :WYTImport, handwriting from the Boox into the project. The tablet syncs to
-- a Dropbox folder: a .txt is its own handwriting recognition, cleaned up here
-- by the model; a .pdf is the pages themselves, transcribed by the model. Each
-- lands as a freewrite, so :WYTPlace puts it where it belongs. The folder is
-- only read: nothing on Dropbox is moved, renamed or changed.
local M = {}

local uv = vim.uv or vim.loop

-- A notebook keeps growing on the tablet, and the file with it: the manifest
-- says how much of each was already brought in, so only what is new comes.
local MANIFEST = "imports.wyt.json"
-- Both providers take about 32 MB a request, and base64 sends a PDF a third
-- larger than it is. A file over this is skipped with a message.
local MAX_SIZE = 20 * 1024 * 1024
-- A paragraph break as a token of its own, so the word diff carries it
-- through and the marked text gets its blank lines back.
local PARA = "\1"

--- What was already imported, by file name; empty when there is no manifest.
function M.read_manifest(project_mod)
    local raw = project_mod.read_file(project_mod.project_root .. MANIFEST)
    local ok, data = pcall(vim.json.decode, raw or "")
    return ok and type(data) == "table" and data or {}
end

--- What is new in the folder, oldest first: { name, kind, text, content, size,
--- mtime } for a .txt, `text` being the part after what was imported; { name,
--- path, kind, from, size, mtime } for a .pdf, read from the page after the
--- last one imported. A .txt whose start no longer matches what was imported is
--- read whole again: it was rewritten, not added to.
function M.pending(project_mod, dir, manifest)
    local out = {}
    for _, name in ipairs(vim.fn.readdir(dir)) do
        local kind = name:lower():match("%.(txt)$") or name:lower():match("%.(pdf)$")
        local path = dir .. name
        -- lstat, and files only: a link in the folder would send whatever it
        -- points at to the provider.
        local stat = kind and uv.fs_lstat(path)
        if stat and stat.type ~= "file" then stat = nil end
        local seen = manifest[name] or {}
        if kind == "txt" and stat then
            local content = (project_mod.read_file(path) or ""):gsub("^\239\187\191", ""):gsub("\r\n", "\n")
            local start = 1
            if seen.bytes and #content >= seen.bytes and vim.fn.sha256(content:sub(1, seen.bytes)) == seen.sha then
                start = seen.bytes + 1
            end
            local text = vim.trim(content:sub(start))
            if text ~= "" then
                out[#out + 1] = { name = name, kind = kind, text = text, content = content,
                    size = stat.size, mtime = stat.mtime.sec }
            end
        elseif kind == "pdf" and stat and (seen.size ~= stat.size or seen.mtime ~= stat.mtime.sec) then
            out[#out + 1] = { name = name, path = path, kind = kind, from = (seen.pages or 0) + 1,
                pages = seen.pages or 0, size = stat.size, mtime = stat.mtime.sec }
        end
    end
    table.sort(out, function(a, b) return a.mtime < b.mtime end)
    return out
end

local function tokens(text)
    local out = {}
    for i, para in ipairs(vim.split(vim.trim(text), "\n%s*\n")) do
        if i > 1 then out[#out + 1] = PARA end
        for w in para:gmatch("%S+") do out[#out + 1] = w end
    end
    return out
end

--- `b` with what changed from `a` marked inline, word by word: `[-was-]{+is+}`.
--- A line diff would mark whole paragraphs, and a misread word is one word.
--- Returns the marked text and how many changes there are.
function M.word_diff(a, b)
    local ta, tb = tokens(a), tokens(b)
    local hunks = vim.diff(table.concat(ta, "\n") .. "\n", table.concat(tb, "\n") .. "\n", { result_type = "indices" })
    local out, ib = {}, 1
    local function take(upto)
        while ib <= upto do out[#out + 1], ib = tb[ib], ib + 1 end
    end
    for _, h in ipairs(hunks) do
        local sa, ca, sb, cb = h[1], h[2], h[3], h[4]
        -- With nothing on b's side, sb is the token the change comes after.
        take(cb == 0 and sb or sb - 1)
        out[#out + 1] = (ca > 0 and ("[-" .. table.concat(ta, " ", sa, sa + ca - 1) .. "-]") or "")
            .. (cb > 0 and ("{+" .. table.concat(tb, " ", sb, sb + cb - 1) .. "+}") or "")
        ib = cb == 0 and sb + 1 or sb + cb
    end
    take(#tb)
    return (table.concat(out, " "):gsub(" ?" .. PARA .. " ?", "\n\n")), #hunks
end

-- A new freewrite for `item`, named by the minute it came in and its source.
local function write_freewrite(project_mod, item, text)
    local dir = project_mod.project_root .. "freewrite/"
    vim.fn.mkdir(dir, "p")
    local base = os.date("%Y-%m-%d-%H%M") .. "-" .. project_mod.slugify(vim.fn.fnamemodify(item.name, ":r"))
    local path, n = dir .. base .. ".md", 1
    while uv.fs_stat(path) do
        n = n + 1
        path = dir .. base .. "-" .. n .. ".md"
    end
    -- The source as a quote, the way a prompt heads a freewrite: Place leaves it
    -- out. On one line: a newline in a file name would start the text with it.
    project_mod.write_file(path, "> Boox: " .. item.name:gsub("%c", " ") .. "\n\n" .. text .. "\n")
    return path
end

--- Run the import over `items`, from M.pending.
function M.run(items)
    local project = require("wyt.project")
    local ui = require("wyt.ui")
    local llm = require("wyt.llm")
    local t = project.t
    local manifest = M.read_manifest(project)
    local imported, changed = {}, false

    -- What the model makes of `item`, handed to `callback`: { text } for a .txt,
    -- { text, pages } for a .pdf; nil when it could not. `note` asks again, with
    -- the last proposal, after Change it….
    local function read(item, note, callback)
        if item.size > MAX_SIZE then
            item.too_big = true
            vim.notify(t("import_too_big"):format(item.name), vim.log.levels.WARN)
            return callback(nil)
        end
        vim.notify(t("import_reading"):format(item.name), vim.log.levels.INFO)
        local function done(result, err)
            if not result then vim.notify(t("llm_error") .. tostring(err), vim.log.levels.WARN) end
            callback(result)
        end
        local ctx = { lang = project.lang, note = note, previous = note and item.result and item.result.text }
        if item.kind == "txt" then
            ctx.text = item.text
            return llm.clean_recognized(ctx, function(text, err) done(text and { text = text }, err) end)
        end
        item.pdf = item.pdf or vim.base64.encode(project.read_file(item.path) or "")
        ctx.pdf, ctx.from = item.pdf, item.from
        llm.transcribe(ctx, done)
    end

    local function finish()
        if changed then
            project.write_file(project.project_root .. MANIFEST, vim.json.encode(manifest) .. "\n")
            project.commit_changes("Save: imported from the Boox")
        end
        if #imported == 0 then return vim.notify(t("import_nothing"), vim.log.levels.INFO) end
        require("wyt.outline").refresh()
        vim.notify(t("import_done"):format(#imported), vim.log.levels.INFO)
        ui.ask_select({ title = t("import_title"), question = t("import_place_q") },
            { t("import_place_now"), t("import_place_later") }, function(choice)
                if choice ~= t("import_place_now") then return end
                ui.edit_file(imported[1])
                require("wyt.place").open()
            end)
    end

    local step
    local function seen(item)
        changed = true
        if item.kind == "txt" then
            manifest[item.name] = { bytes = #item.content, sha = vim.fn.sha256(item.content) }
        else
            -- Never lower: a page count the model got wrong would bring back
            -- pages already imported.
            manifest[item.name] = { size = item.size, mtime = item.mtime,
                pages = math.max(item.pages, item.result.pages) }
        end
    end
    local function take(i, item, text)
        imported[#imported + 1] = write_freewrite(project, item, text)
        seen(item)
        step(i + 1)
    end

    local function menu(i)
        local item, r = items[i], items[i].result
        if item.too_big then return step(i + 1) end
        local title = t("import_title") .. " " .. i .. "/" .. #items .. ": " .. item.name
        local question, choices
        if item.kind == "txt" and r then
            local marked, changes = M.word_diff(item.text, r.text)
            question = changes > 0 and marked or (t("import_unchanged") .. "\n\n" .. r.text)
            choices = { t("import_use"), t("import_change"), t("import_keep"), t("import_skip") }
        elseif item.kind == "txt" then
            -- No model: the recognition is still the writer's text.
            question, choices = item.text, { t("import_keep"), t("import_skip") }
        elseif r and r.text == "" then
            -- A notebook saved again with no new pages: nothing to bring in, and
            -- nothing to read again next time.
            seen(item)
            return step(i + 1)
        elseif r then
            question, choices = r.text, { t("import_it"), t("import_change"), t("import_skip") }
        else
            return step(i + 1)
        end
        ui.ask_select({ title = title, question = question, prompt = t("import_menu") }, choices, function(choice)
            -- Esc stops the run; what was imported stays imported.
            if not choice then return finish() end
            if choice == t("import_skip") then return step(i + 1) end
            if choice == t("import_keep") then return take(i, item, item.text) end
            if choice == t("import_use") or choice == t("import_it") then return take(i, item, r.text) end
            ui.ask_input({ title = t("import_change"), question = t("import_change_q") }, function(note)
                if note == nil then return finish() end
                if note == "" then return menu(i) end
                read(item, note, function(result)
                    if result then item.result = result end
                    menu(i)
                end)
            end)
        end)
    end

    step = function(i)
        local item = items[i]
        if not item then return finish() end
        if item.result ~= nil then return menu(i) end
        read(item, nil, function(result)
            item.result = result or false
            menu(i)
        end)
    end
    step(1)
end

--- `:WYTImport`: what is new in the project's Boox folder, asked for the
--- first time.
function M.open()
    local project = require("wyt.project")
    if not project.setup() then return end
    local t = project.t
    project.outside_dir("import_dir", t("import_title"), t("import_dir_q"), function(dir)
        local items = M.pending(project, dir, M.read_manifest(project))
        if #items == 0 then return vim.notify(t("import_none"):format(dir), vim.log.levels.INFO) end
        M.run(items)
    end)
end

return M
