-- Test runner for WYT. plenary.nvim is not a dependency of this plugin, and
-- `PlenaryBustedDirectory` hangs forever when it is missing, so the suite ships
-- its own harness: the busted API these specs actually use, and nothing else.
--
--   nvim --headless -l tests/runner.lua              every tests/*_spec.lua
--   nvim --headless -l tests/runner.lua types llm    only those specs
--
-- Exits 1 if anything failed, so it is usable from CI or a git hook.

vim.opt.runtimepath:prepend(vim.fn.getcwd())

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

function _G.it(name, body)
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

-- luassert's surface, limited to what the specs use. `assert` stays callable so
-- plain `assert(cond, msg)` keeps working inside a spec.
local function show(v)
    if type(v) == "string" then return string.format("%q", v) end
    return vim.inspect(v)
end

local A = {}

function A.truthy(v, msg)
    if not v then error(msg or ("expected truthy, got " .. show(v)), 2) end
end

function A.falsy(v, msg)
    if v then error(msg or ("expected falsy, got " .. show(v)), 2) end
end

function A.equals(expected, actual, msg)
    if expected ~= actual then
        error(msg or ("expected " .. show(expected) .. "\n     got " .. show(actual)), 2)
    end
end

function A.same(expected, actual, msg)
    if not vim.deep_equal(expected, actual) then
        error(msg or ("expected " .. show(expected) .. "\n     got " .. show(actual)), 2)
    end
end

function A.is_nil(v, msg)
    if v ~= nil then error(msg or ("expected nil, got " .. show(v)), 2) end
end

function A.is_not_nil(v, msg)
    if v == nil then error(msg or "expected not nil, got nil", 2) end
end

function A.matches(pattern, actual, msg)
    if type(actual) ~= "string" or not actual:find(pattern) then
        error(msg or ("expected " .. show(actual) .. " to match " .. show(pattern)), 2)
    end
end

function A.has_no_match(pattern, actual, msg)
    if type(actual) == "string" and actual:find(pattern) then
        error(msg or ("expected " .. show(actual) .. " not to match " .. show(pattern)), 2)
    end
end

A.equal = A.equals
A.is_true = A.truthy
A.is_false = A.falsy
-- `assert.are.equal` and `assert.is.truthy` read better in places; both chain
-- back to the same table so any spelling works.
A.are, A.is, A.has = A, A, A

_G.assert = setmetatable(A, {
    __call = function(_, v, msg)
        if not v then error(msg or "assertion failed", 2) end
        return v
    end,
})

local wanted = {}
for _, name in ipairs(_G.arg or {}) do wanted[name] = true end

local specs = vim.fn.glob("tests/*_spec.lua", false, true)
table.sort(specs)

for _, spec in ipairs(specs) do
    local short = spec:match("([^/\\]+)_spec%.lua$")
    if not next(wanted) or wanted[short] then
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
