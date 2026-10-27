-- A driven session: the real nvim, with the writer's own config and WYT loaded
-- from WYT_PATH, run inside a terminal of this headless nvim. Keys go in through
-- the terminal the way a writer types them; what is on screen is read back over
-- the child's RPC socket, since on Windows the ConPTY hands the rendered screen
-- to stdout and the terminal buffer stays empty.
--
--   nvim --headless -u NONE -l tests/drive.lua [out_dir]
--
-- Not a spec: it needs the writer's config (Telescope draws the menus) and a
-- real API key, so every run spends a few model calls. It caught what the specs
-- could not: freewrite text glued to its prompt once typed. Exits 1 when a
-- check fails; snapshots of each step and results.txt land in out_dir.

-- The system temp folder, not vim.fn.tempname(), which nvim deletes on exit
-- and the snapshots with it.
local default_out = (vim.uv or vim.loop).os_tmpdir() .. "/wyt-drive-" .. os.date("%Y%m%d-%H%M%S")
local OUT = vim.fn.fnamemodify(arg[1] or default_out, ":p"):gsub("\\", "/")
if not OUT:match("/$") then OUT = OUT .. "/" end
vim.fn.mkdir(OUT, "p")
local DAY = 24 * 3600

local function write(p, s) local f = assert(io.open(p, "wb")); f:write(s); f:close() end
local function read(p)
    local f = io.open(p, "rb")
    if not f then return nil end
    local s = f:read("*a"); f:close(); return s
end
local function sh(args, env)
    local cmd = { "git", "-C", ROOT, "-c", "user.name=t", "-c", "user.email=t@t" }
    return vim.system(vim.list_extend(cmd, args), { text = true, env = env }):wait()
end

-- An essay at its depth limit, two scenes, last written three days ago: the
-- age that makes the recap summarise the scene.
ROOT = vim.fn.tempname():gsub("\\", "/") .. "/port/"
vim.fn.mkdir(ROOT, "p")
write(ROOT .. "config.wyt.yml", "lang: en\ntype: essay\ncontent_type: content\nsections: false\nname: The Port\n")
write(ROOT .. "plan.wyt.md", table.concat({
    "# The Port", "", "## Description", "",
    "A town during a dock strike, seen by a woman who arrives on the night ferry.", "",
    "## Ideas", "", "- the harbour master [Group: The arrival]", "- the union hall [Group: The strike]",
    "- a dog on the pier", "",
    "## Group: The arrival [Implemented]", "- the harbour master", "",
    "## Group: The strike [Implemented]", "- the union hall", "",
}, "\n"))
write(ROOT .. "text.wyt.md", table.concat({
    "## Group: The arrival", "", "She came on the night ferry.", "The port was closed.", "",
    "*Create a paragraph about: [the harbour master]*", "",
    "## Group: The strike", "", "Nobody unloaded anything that week.", "",
    "*Create a paragraph about: [the union hall]*", "",
}, "\n"))
sh({ "init", "-q" })
sh({ "add", "." })
local when = "@" .. (os.time() - 3 * DAY) .. " +0000"
sh({ "commit", "-q", "-m", "Save: text.wyt.md" },{ GIT_AUTHOR_DATE = when, GIT_COMMITTER_DATE = when })

vim.o.columns, vim.o.lines = 110, 42
local addr = vim.fn.has("win32") == 1 and ([[\\.\pipe\wyt-drive-]] .. vim.fn.getpid()) or vim.fn.tempname()
local job = vim.fn.jobstart({ "nvim", "--listen", addr, "text.wyt.md" }, { term = true, cwd = ROOT })

local rpc
local blocked = {}
local function child(code)
    if not rpc then
        local ok, ch = pcall(vim.fn.sockconnect, "pipe", addr, { rpc = true })
        if not ok or ch == 0 then return "" end
        rpc = ch
    end
    -- nvim_get_mode answers even while the child waits on a prompt; any other
    -- request would hang until someone dismissed it.
    local mode = vim.rpcrequest(rpc, "nvim_get_mode")
    if mode.blocking then
        blocked[#blocked + 1] = mode.mode
        return "BLOCKED mode=" .. mode.mode
    end
    local ok, r = pcall(vim.rpcrequest, rpc, "nvim_exec_lua", code, {})
    return ok and r or ("RPC ERROR " .. tostring(r))
end

-- Every window on the child's tab, floats included (the editor, the brief
-- panel, Telescope's prompt and results), then its messages.
local SCREEN = [[
    local out = {}
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        local b = vim.api.nvim_win_get_buf(w)
        local float = vim.api.nvim_win_get_config(w).relative ~= "" and " [float]" or ""
        out[#out + 1] = "=== " .. vim.fn.fnamemodify(vim.api.nvim_buf_get_name(b), ":t") .. float
        vim.list_extend(out, vim.api.nvim_buf_get_lines(b, 0, -1, false))
    end
    out[#out + 1] = "=== messages"
    out[#out + 1] = vim.fn.execute("messages")
    return table.concat(out, string.char(10))
]]
local function screen() return child(SCREEN) end

local shot = 0
local function snap(name)
    shot = shot + 1
    write(string.format("%s%02d-%s.txt", OUT, shot, name), screen())
end
local function wait_for(text, ms)
    local ok = vim.wait(ms or 15000, function() return screen():find(text, 1, true) ~= nil end, 100)
    if not ok then snap("TIMEOUT-" .. text:gsub("[^%w]", "_")) end
    return ok
end
local function send(keys) vim.fn.chansend(job, keys) end
-- The fixed waits give a picker or a save time to land; the model replies are
-- the only slow step, and wait_for covers those.
local function pause(ms) vim.wait(ms) end

local results, failed = {}, false
local function check(name, ok, detail)
    failed = failed or not ok
    results[#results + 1] = (ok and "PASS " or "FAIL ") .. name .. (detail and ("  (" .. detail .. ")") or "")
end

check("nvim starts with the text", wait_for("She came on the night ferry", 30000))
pause(1500)

send(":WYTToday\r")
check(":WYTToday shows the brief and menu", wait_for("Freewrite", 60000))
pause(800)
snap("today-brief")
local s = screen()
check("recap says 3 days ago", s:find("3 days ago", 1, true) ~= nil)
check("last paragraph word for word", s:find("Nobody unloaded anything that week", 1, true) ~= nil)
check("continue option names the scene", s:find("Continue: The Port", 1, true) ~= nil)
check("open placeholders listed", s:find("Write: the", 1, true) ~= nil)

-- Through the real picker: type to filter, confirm, then write and save.
send("Freewrite")
pause(600)
send("\r")
pause(1500)
send("The gate was chained and a man in a grey coat held the key.")
pause(300)
snap("freewrite-typed")
send("\27:w\r")
pause(2000)
snap("freewrite-saved")
if screen():find("^BLOCKED") then
    check("save leaves no prompt to dismiss", false, table.concat(blocked, ","))
    send("\r")
    pause(800)
end
local opts = child([[return vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":t")
    .. " nu=" .. tostring(vim.wo.number) .. " scl=" .. vim.wo.signcolumn
    .. " wrap=" .. tostring(vim.wo.wrap) .. " lbr=" .. tostring(vim.wo.linebreak)]])
check("freewrite buffer is bare", opts:find("nu=false scl=no wrap=true lbr=true", 1, true) ~= nil, opts)
local files = vim.fn.readdir(ROOT .. "freewrite")
local fw = files[1] and read(ROOT .. "freewrite/" .. files[1]) or ""
check("freewrite keeps a blank line under its prompt", fw:match("^> .+\n\nThe gate was chained") ~= nil, files[1])
check("freewrite save committed", sh({ "log", "--format=%s" }).stdout:find("Save: freewrite/", 1, true) ~= nil)

-- A freewrite commit is not where the prose stopped.
send(":WYTToday\r")
wait_for("Freewrite", 60000)
pause(800)
snap("today-again")
check("second recap still in the text", screen():find("3 days ago", 1, true) ~= nil)
send("\27\27")
pause(600)

send(":WYTNav\r")
pause(2000)
snap("nav")
check(":WYTNav opens a picker", screen():find("Navigate project", 1, true) ~= nil)
send("\27\27")
pause(600)
send(":WYTExport\r")
pause(3000)
local export = read(ROOT .. "export.wyt.md") or ""
check(":WYTExport assembles the prose", export:find("Nobody unloaded anything that week", 1, true) ~= nil)
check("export leaves freewrite out", export:find("grey coat", 1, true) == nil)

-- Place, on the freewrite: the model may fairly keep the chunk, so moving it is
-- checked only when the menu offered to.
send(":edit freewrite/" .. files[1] .. "\r")
pause(800)
send(":WYTPlace\r")
check(":WYTPlace shows a chunk and its menu", wait_for("Leave it in freewrite", 60000))
pause(800)
snap("place-menu")
if screen():find("Place it there", 1, true) then
    send("Place it")
    pause(600)
    send("\r")
    pause(2500)
    snap("placed")
    check("placed text lands unchanged", (read(ROOT .. "text.wyt.md") or ""):find("a man in a grey coat held the key", 1, true) ~= nil)
    check("place commit counts as writing", sh({ "log", "-1", "--format=%s" }).stdout:find("^Save: placed freewrite/") ~= nil)
else
    send("\27\27")
    pause(800)
end

snap("final")
local m = screen()
check("no Lua errors in :messages", not (m:find("E5108", 1, true) or m:find("stack traceback", 1, true)))

send("\27:qa!\r")
pause(1500)
write(OUT .. "results.txt", table.concat(results, "\n") .. "\n")
io.stderr:write(table.concat(results, "\n") .. "\nsnapshots: " .. OUT .. "\n")
vim.cmd(failed and "cquit 1" or "qa!")
