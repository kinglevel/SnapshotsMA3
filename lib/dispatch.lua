-- lib/dispatch.lua (Snapshots.dispatch) — the command-surface ROUTER
-- (INVK-02/03/04, RCL-03/05/06). This is the phase deliverable: the pure,
-- dependency-injected seam Main calls to turn a parsed arg into a recall/store/
-- clear against injected collaborators, plus the empty-arg manager placeholder
-- and the graceful parse-error surface.
--
-- BOUNDARY DISCIPLINE (the #1 rule, D-06): dispatch reaches NO MA3
-- console global at all — not the command/object accessors, the persistence vars,
-- the sysmon print, nor the scheduler/clock. Every console effect is delegated to
-- an INJECTED collaborator (deps.store / deps.ma3 own the only real console reach —
-- each pcall-wrapped inside those modules). Main assembles the deps bag from the
-- Snapshots.* namespace at call time and hands it in.
--   * deps = { store, ma3, model, fade, breakdown, notify, new_id? }
--   * args.parse is reached via Snapshots.args at CALL time (SHARED-B), NOT via
--     deps and NEVER as a file-scope upvalue (sibling load order isn't guaranteed).
--
-- COMPOSITION (no re-implementation — the collaborators are already green):
--   recall : model.recall_plan → (breakdown.select_targets, shape-convert) →
--            fade.resolve_time → ma3.recall   (ma3 owns skip+notify, RCL-06)
--   store  : ma3.capture → model.set_member → store.save  (re-capture existing);
--            a brand-new name creates an EMPTY snapshot (Phase 8 assigns members)
--   clear  : empty members, keep the snapshot → store.save
-- Never load()/loadstring() stored data (code-injection hole) — only plain fields.
Snapshots = Snapshots or {}   -- idempotent bootstrap (NEVER `= {}` — wipes siblings)
local Dispatch = {}

-- ── PURE HELPERS ────────────────────────────────────────────────────────────────
-- No MA3 reach, no injected deps; directly unit-testable.

-- Pure case-insensitive matcher over a store.load().snapshots map ({[id]=snap}).
-- Returns a list of {id, snap} hits: #hits 0 → not found, 1 → act, >1 → ambiguous
-- (the caller acts on NONE). Snapshots are keyed by opaque id; name is a data field.
local function find_by_name(snapshots_map, name)
  local want, hits = tostring(name):lower(), {}
  for id, snap in pairs(snapshots_map or {}) do
    if tostring(snap.name):lower() == want then hits[#hits + 1] = { id = id, snap = snap } end
  end
  return hits
end

-- Deterministic id generator (A1, LOCKED — no clock or randomness): the smallest
-- integer n>=1 whose tostring is not already a key in the collection. Fills the
-- lowest free slot, so it is stable and unit-testable. Exposed as a table field so
-- Main can override it via deps.new_id and tests can call it directly.
function Dispatch.next_free_id(snapshots_map)
  snapshots_map = snapshots_map or {}
  local n = 1
  while snapshots_map[tostring(n)] ~= nil do n = n + 1 end
  return tostring(n)
end

-- ── VERB HANDLERS ────────────────────────────────────────────────────────────────
-- Each composes injected collaborators only.

-- RECALL (Core Value). ⚠ breakdown shape conversion is MANDATORY: select_targets
-- emits {ref, to=100} but model/ma3 speak {ref, value}. Passing {ref,to} straight
-- to ma3.recall would drive every breakdown target to nil.
local function do_recall(intent, snap, deps)
  local plan = deps.model.recall_plan(snap)                    -- [{ref,value}] assigned-only
  if intent.breakdown then
    local bt = deps.breakdown.select_targets(plan)             -- [{ref, to=100}]  ⚠ .to
    plan = {}
    for _, t in ipairs(bt) do plan[#plan + 1] = { ref = t.ref, value = t.to } end  -- → {ref,value}
  end
  local t = deps.fade.resolve_time(snap.fade, intent.fade)     -- RCL-03 arg-over-default
  deps.ma3.recall(plan, t)                                     -- ma3 owns skip+notify (RCL-06)
end

-- STORE (existing snapshot): re-capture the live values of the CURRENT members
-- only (Phase 8 adds assignment) and persist. capture→set_member dedups by
-- schema.key, so a re-store updates values in place without duplicating members.
local function do_store(intent, snap, id, deps)
  local refs, was = {}, {}
  for _, m in ipairs(snap.members) do
    refs[#refs + 1] = m.ref
    was[Snapshots.schema.key(m.ref)] = (m.assigned ~= false)   -- preserve parked state (D-10 / WR-01)
  end
  local caps = deps.ma3.capture(refs)                          -- [{ref,value}] (empty refs → empty)
  for _, c in ipairs(caps) do
    -- re-store UPDATES values in place; it must NOT un-park a parked member (assigned=false).
    deps.model.set_member(snap, c.ref, was[Snapshots.schema.key(c.ref)] ~= false, c.value)
  end
  deps.store.save(id, snap)
end

-- CLEAR (existing snapshot): drop all members but KEEP the named snapshot, then
-- persist (the snapshot survives; only its stored positions are wiped).
local function do_clear(intent, snap, id, deps)
  snap.members = {}
  deps.store.save(id, snap)
end

-- ── ENTRY SEAMS ──────────────────────────────────────────────────────────────────

-- INVK-02: empty/whitespace arg → the manager. LAZY read only (proven never to
-- write, test_store.lua:54-59); no save/clear here. The real console-overlay build
-- lives in lib/ui/manager.lua and is reached ONLY through the INJECTED deps.ui
-- collaborator — dispatch itself stays MA3-free (boundary, T-07-10/11/12). When ui
-- is absent (load race / off-desk), degrade to a notify rather than a nil-index crash.
function Dispatch.open_manager(deps)
  deps.store.load()                                    -- lazy read; NEVER writes (test_store proves)
  if deps.ui and deps.ui.open then deps.ui.open(deps)  -- console layer builds the overlay
  else deps.notify("manager UI unavailable") end       -- off-desk / degraded fallback
end

-- Route a parsed intent against the live collection. Resolves name → snapshot,
-- guarding the 0-miss and >1-ambiguous cases (act on NONE), then dispatches to the
-- verb handler. (store/clear arms land in Task 2.)
function Dispatch.run(intent, deps)
  local coll = deps.store.load()                               -- single read (IN-01)
  local hits = find_by_name(coll.snapshots, intent.name)
  if #hits == 0 then
    if intent.verb == "store" then                             -- create-on-store (A1, LOCKED)
      local map  = coll.snapshots or {}
      local id   = (deps.new_id or Dispatch.next_free_id)(map) -- deterministic next-free id
      local snap = deps.model.new_snapshot(intent.name)        -- EMPTY (Phase 8 assigns members)
      return deps.store.save(id, snap)
    end
    return deps.notify("no snapshot named '" .. tostring(intent.name) .. "'")
  end
  if #hits > 1 then
    return deps.notify("ambiguous name '" .. tostring(intent.name) .. "' — rename in the manager")
  end
  local id, snap = hits[1].id, hits[1].snap
  if intent.verb == "recall" then
    do_recall(intent, snap, deps)
  elseif intent.verb == "store" then
    do_store(intent, snap, id, deps)
  elseif intent.verb == "clear" then
    do_clear(intent, snap, id, deps)
  end
end

-- THE testable seam Main calls (INVK-02/03/04). One pcall wraps the whole body so a
-- throwing collaborator (store/ma3) yields a tidy notify line, never a raw traceback
-- that aborts the invocation (T-06-04). Whitespace-only normalizes to the empty path.
function Dispatch.execute(arg_str, deps)
  local ok, err = pcall(function()
    local s = (tostring(arg_str):gsub("^%s+", ""):gsub("%s+$", ""))  -- trim to detect empty
    if s == "" then return Dispatch.open_manager(deps) end           -- INVK-02 (stays SILENT)
    local intent, perr = Snapshots.args.parse(s)                      -- call-time cross-ref
    if not intent then return deps.notify(perr.msg) end               -- INVK-04 (reuse the msg)
    deps.notify(s)                                                    -- UI-03: echo the valid command arg
    Dispatch.run(intent, deps)                                        -- INVK-03
  end)
  if not ok then deps.notify("command failed: " .. tostring(err)) end  -- never crashes
end

Snapshots.dispatch = Dispatch   -- attach under the namespace key
return Dispatch                 -- RETURN THE TABLE (tests dofile it for this value)
