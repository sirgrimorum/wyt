-- Test runner for WYT. plenary.nvim is not a dependency of this plugin, and
-- `PlenaryBustedDirectory` hangs forever when it is missing, so the suite ships
-- its own harness: the busted API these specs actually use, and nothing else.
--
--   nvim --headless -l tests/runner.lua              every tests/*_spec.lua
--   nvim --headless -l tests/runner.lua types llm    only those specs
--
-- Exits 1 if anything failed, so it is usable from CI or a git hook.

-- Work from the repo root whatever the cwd: the specs are globbed and
-- `require("tests.helpers")` is resolved relative to it, so a run started
-- elsewhere used to find nothing and report success.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.fn.chdir(root)
vim.opt.runtimepath:prepend(root)

local state = {
    path = {},       -- describe() names we are nested inside
    passed = 0,
    failed = {},     -- { name, err }
    before = {},     -- before_each stack, one list per describe level
}

local function full_name(name)
    local parts = vim.deepcopy(state.path)
    parts[#parts + 1] = name
    return table.concat(parts, " ")
end

function _G.describe(name, body)
    state.path[#state.path + 1] = name
    state.before[#state.before + 1] = {}
    local ok, err = pcall(body)
    if not ok then
        state.failed[#state.failed + 1] = { full_name("(describe body)"), err }
    end
    state.before[#state.before] = nil
    state.path[#state.path] = nil
end

function _G.before_each(fn)
    local level = state.before[#state.before]
    if level then level[#level + 1] = fn end
end

-- Every seam a spec stubs, put back after each test however it ended. Specs
-- restore inline, so a failing one used to leave its stub for every later
-- spec, and the full run and a single spec ran against different code.
local SEAMS = {
    { vim, "notify" }, { vim, "health" }, { vim.ui, "select" }, { vim.ui, "input" },
    { require("wyt.llm"), "generate_text" }, { require("wyt.ui"), "edit_file" },
}
local loc = require("wyt.localization")

local function snapshot()
    local saved = { columns = vim.o.columns, lang = loc.lang }
    for i, seam in ipairs(SEAMS) do saved[i] = seam[1][seam[2]] end
    return saved
end

local function restore(saved)
    for i, seam in ipairs(SEAMS) do seam[1][seam[2]] = saved[i] end
    vim.o.columns = saved.columns
    loc.lang = saved.lang
end

local function run_test(name, body)
    for _, level in ipairs(state.before) do
        for _, fn in ipairs(level) do
            local ok, err = pcall(fn)
            if not ok then
                state.failed[#state.failed + 1] = { full_name(name), "before_each: " .. tostring(err) }
                return
            end
        end
    end
    local ok, err = pcall(body)
    if ok then
        state.passed = state.passed + 1
    else
        state.failed[#state.failed + 1] = { full_name(name), err }
    end
end

function _G.it(name, body)
    local saved = snapshot()
    run_test(name, body)
    restore(saved)
end

-- luassert's surface, limited to what the specs use. `assert` stays callable so
-- plain `assert(cond, msg)` keeps working inside a spec.
local function show(v)
    if type(v) == "string" then return string.format("%q", v) end
    return vim.inspect(v)
end

local A = {}

-- A spec's message says what the check means; the default says what came back.
-- Both are needed to act on a failure, so the message leads rather than replaces.
local function fail(msg, default)
    error((msg and (msg .. "\n     ") or "") .. default, 3)
end

function A.truthy(v, msg)
    if not v then fail(msg, "expected truthy, got " .. show(v)) end
end

function A.falsy(v, msg)
    if v then fail(msg, "expected falsy, got " .. show(v)) end
end

function A.equals(expected, actual, msg)
    if expected ~= actual then
        fail(msg, "expected " .. show(expected) .. "\n     got " .. show(actual))
    end
end

function A.same(expected, actual, msg)
    if not vim.deep_equal(expected, actual) then
        fail(msg, "expected " .. show(expected) .. "\n     got " .. show(actual))
    end
end

function A.is_nil(v, msg)
    if v ~= nil then fail(msg, "expected nil, got " .. show(v)) end
end

function A.is_not_nil(v, msg)
    if v == nil then fail(msg, "expected not nil, got nil") end
end

function A.matches(pattern, actual, msg)
    if type(actual) ~= "string" or not actual:find(pattern) then
        fail(msg, "expected " .. show(actual) .. " to match " .. show(pattern))
    end
end

-- Not a string fails too: a prompt that was never captured is nil, and "nil
-- does not mention long_novel" would pass while testing nothing.
function A.has_no_match(pattern, actual, msg)
    if type(actual) ~= "string" or actual:find(pattern) then
        fail(msg, "expected " .. show(actual) .. " not to match " .. show(pattern))
    end
end

_G.assert = setmetatable(A, {
    __call = function(_, v, msg)
        if not v then error(msg or "assertion failed", 2) end
        return v
    end,
})

local wanted, missing = {}, {}
for _, name in ipairs(_G.arg or {}) do wanted[name], missing[name] = true, true end

local specs = vim.fn.glob("tests/*_spec.lua", false, true)
table.sort(specs)

local ran_any = false
for _, spec in ipairs(specs) do
    local short = spec:match("([^/\\]+)_spec%.lua$")
    if not next(wanted) or wanted[short] then
        ran_any = true
        missing[short] = nil
        local before = state.passed
        local failed_before = #state.failed
        local ok, err = pcall(dofile, spec)
        if not ok then
            state.failed[#state.failed + 1] = { short .. " (failed to load)", err }
        end
        local ran = (state.passed - before) + (#state.failed - failed_before)
        print(string.format("%-22s %d passed, %d failed  (%d)",
            short, state.passed - before, #state.failed - failed_before, ran))
    end
end

-- A misspelt name must not pass as "0 failed".
for name in pairs(missing) do
    state.failed[#state.failed + 1] = { name, "no tests/" .. name .. "_spec.lua" }
end
if not ran_any then
    state.failed[#state.failed + 1] = { "(runner)", "no spec ran" }
end

if #state.failed > 0 then
    print("")
    print("FAILURES")
    for _, f in ipairs(state.failed) do
        print("  " .. f[1])
        for line in tostring(f[2]):gmatch("[^\n]+") do print("      " .. line) end
    end
end

print("")
print(string.format("%d passed, %d failed", state.passed, #state.failed))
if #state.failed > 0 then vim.cmd("cquit 1") end
