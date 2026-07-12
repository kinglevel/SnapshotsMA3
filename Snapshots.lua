Snapshots = Snapshots or {}   -- idempotent bootstrap (NEVER `= {}`)

local pluginName    = select(1, ...)
local componentName = select(2, ...)
local signalTable   = select(3, ...)
local my_handle     = select(4, ...)

-- ── local helpers ────────────────────────────────────────────────────────────
local function safe_tostring(v)
  local ok, s = pcall(tostring, v); if ok and s then return s end; return ""
end
local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- ── sysmon adapter (D-04; Printf → System Monitor; pcall-guarded) ────────────
-- One call site so Phase 6 (skip-and-notify) and Phase 9 (monitor strip) reuse it.
function Snapshots.log(msg)
  local s = "Snapshots: " .. safe_tostring(msg)
  -- UI-03: mirror this display line onto the System Monitor strip. Call-time guarded
  -- (`if Snapshots.monitor`) + pcall so an absent monitor (load race) degrades silently
  -- and NEVER crosses the boundary or crashes the invocation (T-09-10).
  pcall(function() if Snapshots.monitor then Snapshots.monitor.push(s) end end)
  pcall(function() Printf("Snapshots: %s", safe_tostring(msg)) end)   -- UNCHANGED (real System Monitor)
end

-- call-time version lookup (Pattern 2 / Pitfall 4 — NEVER file-scope capture)
local function ver()
  return (Snapshots.version and Snapshots.version.STRING) or "?"
end

-- ── Main: dispatch shape (D-05) ──────────────────────────────────────────────
-- Thin entry seam (INVK-02/03): normalize the raw arg, assemble the collaborator
-- deps bag from the Snapshots.* namespace at CALL time (never file-scope upvalues —
-- sibling load order is not guaranteed), and hand it to dispatch inside
-- a belt-and-suspenders pcall (T-06-04: no arg ever crashes the console). Dispatch
-- owns the empty/non-empty split, so Main carries no routing/parse logic.
local function Main(display_handle, argument)
  local arg_str = ""
  if argument ~= nil then
    arg_str = trim(safe_tostring(argument))
    if arg_str == "nil" then arg_str = "" end
  end
  local deps = {
    store     = Snapshots.store,
    ma3       = Snapshots.ma3,
    model     = Snapshots.model,
    fade      = Snapshots.fade,
    breakdown = Snapshots.breakdown,
    notify    = Snapshots.log,                          -- already prefixes "Snapshots: "
    new_id    = Snapshots.dispatch and Snapshots.dispatch.next_free_id,
    manager   = Snapshots.manager,                      -- pure lifecycle (UI handlers call it)
    ui        = Snapshots.ui and Snapshots.ui.manager,  -- console open() collaborator (07-04 seam)
  }
  local ok = pcall(function() Snapshots.dispatch.execute(arg_str, deps) end)
  if not ok then Snapshots.log("internal error (see log)") end   -- belt-and-suspenders
end

return Main   -- ONLY. Never also return a cleanup fn (Pitfall 2: tears the plugin down).
