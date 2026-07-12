-- tests/helpers.lua — off-console test harness (DEV-02 / D-06).
-- Kept: singleton guard, thisDir, the ONE require("json") package.path aug,
-- namespace bootstrap, loadModule, assertion API (+ new assertNil).
-- OMITTED on purpose: MA3-globals stubs, fakeRunner, lfs cpath block, and the
-- opt-in Phase-4 mock layer — those belong to Phase 4 and would defeat the
-- boundary smoke test.

if _G.__SNAP_TEST_HELPERS then return _G.__SNAP_TEST_HELPERS end  -- shared singleton

local function thisDir() return debug.getinfo(1,"S").source:sub(2):match("(.*/)") or "./" end
local HERE = thisDir()

-- Resolve vendored rxi/json.lua via require("json") off-desk (mirrors runtime).
-- THE ONLY package.path line Phase 1 needs.
package.path = package.path .. ";" .. HERE .. "../lib/vendor/?.lua"

-- BOUNDARY POLICY (DEV-02 / D-06): Cmd, Obj, Root, GlobalVars are intentionally
-- LEFT UNDEFINED. Any pure-logic reach for them must crash loudly in tests.
-- (Phase 4 adds an in-memory GlobalVars/SetVar/GetVar/DelVar mock opt-in — NOT here.)

_G.Snapshots = _G.Snapshots or {}   -- bootstrap so dofile'd modules attach

local M = { passed = 0, failed = 0 }
function M.loadModule(rel) return dofile(HERE .. "../lib/" .. rel) end
-- Assertion helpers signal failure purely by error(...); M.run's pcall handler
-- is the single place that increments M.failed (avoids double-counting — IN-01).
function M.assertEq(a, e, msg)
  if a ~= e then
    error(string.format("%s: expected %s, got %s", msg or "assertEq", tostring(e), tostring(a)), 2)
  end
  M.passed = M.passed + 1
end
function M.assertTrue(c, msg)
  if not c then error(msg or "assertTrue: got "..tostring(c), 2) end
  M.passed = M.passed + 1
end
function M.assertNil(v, msg)
  if v ~= nil then error((msg or "assertNil").." got "..tostring(v), 2) end
  M.passed = M.passed + 1
end
function M.assertNear(a, e, eps, msg)
  eps = eps or 1e-3
  if math.abs(a - e) > eps then
    error(string.format("%s: expected %s±%s, got %s", msg or "assertNear", tostring(e), tostring(eps), tostring(a)), 2)
  end
  M.passed = M.passed + 1
end
function M.run(name, fn)
  local ok, err = pcall(fn)
  if ok then print("OK   "..name) else M.failed = M.failed + 1; print("FAIL "..name..": "..tostring(err)) end
end
function M.summary() print(string.format("passed=%d failed=%d", M.passed, M.failed)); return M.failed == 0 end

-- OPT-IN in-memory GlobalVars mock (Phase 4). The default
-- harness still leaves these four globals UNDEFINED (boundary policy) — these
-- functions install them ONLY when a test asks, and uninstall restores nil.
function M.installGlobalVarsMock(seed)
  local store = seed or {}                       -- { ["Snapshots"]=<json string>, ... }
  _G.GlobalVars = function() return "__GV__" end
  _G.GetVar     = function(_, k) return store[k] end
  _G.SetVar     = function(_, k, v) store[k] = v end
  _G.DelVar     = function(_, k) store[k] = nil end
  return store                                    -- test can seed / inspect directly
end
function M.uninstallGlobalVarsMock()
  _G.GlobalVars, _G.GetVar, _G.SetVar, _G.DelVar = nil, nil, nil, nil
end
-- teardown-paired wrapper — restores the four globals to nil even if fn errors,
-- so it CANNOT leak into test_boundary.lua (RESEARCH Pitfall 1).
function M.withGlobalVarsMock(seed, fn)
  local store = M.installGlobalVarsMock(seed)
  local ok, err = pcall(fn, store)
  M.uninstallGlobalVarsMock()
  if not ok then error(err, 0) end
end
-- Optional opt-in Printf capture so the corrupt-path notify can be asserted.
-- Also teardown-paired; Printf is an MA3 global left undefined by default.
function M.withPrintfCapture(fn)
  local msgs = {}
  _G.Printf = function(...) msgs[#msgs + 1] = table.concat({...}, "\t") end
  local ok, err = pcall(fn, msgs)
  _G.Printf = nil
  if not ok then error(err, 0) end
end

-- OPT-IN adapter MA3 mock (Phase 5, RESEARCH Pitfall 7). The
-- default harness still leaves Root/ObjectList/Timer/Time/Printf UNDEFINED —
-- these install them ONLY when a test asks, and uninstall restores nil.

-- mockHandle(spec) — a fake MA3 object handle. GetFader/SetFader are METHODS
-- (handle:GetFader / handle:SetFader), matching lib/ma3.lua's call shapes. Its
-- SetFader records {guid,value} into self._writes (wired by installAdapterMock)
-- so tween / instant-set writes are assertable. spec = {guid,class,fader,name,children}.
function M.mockHandle(spec)
  spec = spec or {}
  local self = { _children = spec.children or {}, _fader = spec.fader,
                 _guid = spec.guid, _class = spec.class, _name = spec.name,
                 _assigned = spec.assigned, _writes = nil }
  function self:Children() return self._children end
  function self:Count()    return #self._children end
  function self:Ptr(i)     return self._children[i] end
  function self:GetClass() return self._class end
  function self:GetAssignedObj() return self._assigned end   -- executor → its hosted object
  function self:Get(prop)                       -- MA3 form is Get("GUID",0)/Get("Name",0)
    if prop == "GUID" then return self._guid
    elseif prop == "Name" then return self._name end
    return nil
  end
  function self:GetFader() return self._fader end
  function self:SetFader(t)
    self._fader = t and t.value
    if self._writes then self._writes[#self._writes + 1] = { guid = self._guid, value = self._fader } end
  end
  return self
end

function M.installAdapterMock(seed)
  seed = seed or {}
  local writes, msgs, timers = {}, {}, {}
  local t = seed.time_start or 1000.0
  local step = seed.time_step or 0.02
  -- wire the shared write log into every seeded handle so SetFader records
  local function wire(list) for _, hnd in ipairs(list or {}) do hnd._writes = writes end end
  wire(seed.groups); wire(seed.sequences); wire(seed.presets); wire(seed.masters)
  -- assemble the live-verified walk tree from the seed lists
  local presetPool = M.mockHandle{ children = seed.presets or {} }   -- one preset pool (Color, ...)
  local datapool   = M.mockHandle{ class = "Pool" }
  datapool.Groups      = M.mockHandle{ children = seed.groups or {} }
  datapool.Sequences   = M.mockHandle{ children = seed.sequences or {} }
  datapool.PresetPools = M.mockHandle{ children = { presetPool } }
  local page           = M.mockHandle{ children = seed.execs or {} }   -- one page of executors
  datapool.Pages       = M.mockHandle{ children = { page } }
  local masterCat = M.mockHandle{ children = seed.masters or {} }    -- one category (e.g. Grand)
  local root = { ShowData = {
    DataPools = M.mockHandle{ children = { datapool } },
    Masters   = M.mockHandle{ children = { masterCat } },
  } }
  _G.Root = function() return root end
  _G.ObjectList = function(name) return (seed.objectlist or {})[name] or {} end
  _G.Timer = function(fn, interval, iters, cleanup)
    timers[#timers + 1] = { fn = fn, interval = interval, iters = iters or 1, cleanup = cleanup }
    if not seed.manual_timer then                 -- synchronous by default → deterministic tween
      for _ = 1, (iters or 1) do fn() end
      if cleanup then cleanup() end
    end
  end
  _G.Time = function() t = t + step; return t end  -- monotonic float stopwatch (elapsed-based u)
  _G.Printf = function(...) msgs[#msgs + 1] = table.concat({ ... }, "\t") end
  return { writes = writes, msgs = msgs, timers = timers }
end

function M.uninstallAdapterMock()
  _G.Root, _G.ObjectList, _G.Timer, _G.Time, _G.Printf = nil, nil, nil, nil, nil
end

-- teardown-paired wrapper — restores ALL five globals to nil even if fn errors,
-- so it CANNOT leak into test_boundary.lua (which asserts _G.Root == nil).
function M.withAdapterMock(seed, fn)
  local ctl = M.installAdapterMock(seed)
  local ok, err = pcall(fn, ctl)
  M.uninstallAdapterMock()
  if not ok then error(err, 0) end
end

_G.__SNAP_TEST_HELPERS = M
return M
