-- lib/manager.lua (Snapshots.manager) — the PURE, store-injected snapshot
-- LIFECYCLE (SNAP-01 create / SNAP-03 rename / SNAP-04 clear / SNAP-05 delete,
-- keyed by id) plus a pure snapshot-list VIEW-MODEL (SNAP-02 list_rows). This is
-- where snapshot management is AUTOMATABLY proven off-console with a spy store —
-- the console overlay render (Plan 03) is a thin adapter over this module and holds
-- ZERO lifecycle logic (every button handler is a one-line Snapshots.manager.* call).
--
-- BOUNDARY DISCIPLINE (the #1 rule, D-06): manager reaches NO MA3
-- console global at all — persistence is delegated to an INJECTED store collaborator
-- (deps.store owns the only real console reach, pcall-wrapped inside store.lua).
-- Cross-refs (Snapshots.dispatch.next_free_id / deps.model) are resolved at CALL
-- time inside function bodies, NEVER captured as file-scope upvalues (sibling load
-- order isn't guaranteed — SHARED-B / Pitfall 3). deps = { store, model, new_id? }.
-- Never load()/loadstring() stored data (code-injection hole) — only plain fields.
Snapshots = Snapshots or {}   -- idempotent bootstrap (NEVER `= {}` — wipes siblings)
local Manager = {}

-- Trim leading/trailing whitespace; "" (or nil / whitespace-only) is invalid.
-- A name string is plain data — it is stored via json.encode (store.lua), never
-- load()/eval'd, so no name can execute (T-07-03).
local function clean_name(name)
  return (tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- SNAP-01: fresh deterministic id → empty named snapshot → persist just that id.
-- Empty/whitespace/nil name rejected (returns nil, NO write). Duplicate names are
-- ALLOWED (A3 — snapshots are id-keyed; there is no duplicate-name collision guard).
function Manager.create(deps, name)
  local nm = clean_name(name)
  if nm == "" then return nil end
  local coll = deps.store.load()
  local map  = coll.snapshots or {}
  local id   = (deps.new_id or Snapshots.dispatch.next_free_id)(map)  -- call-time cross-ref
  local snap = deps.model.new_snapshot(nm)                            -- {name, fade=0, members={}}
  return deps.store.save(id, snap) and id or nil
end

-- SNAP-03: mutate the NAME only; members/fade untouched; store.save merges just
-- this id (peers preserved). Blank new name or unknown id → false, NO write.
function Manager.rename(deps, id, newName)
  local nm = clean_name(newName)
  if nm == "" then return false end
  local coll = deps.store.load()
  local snap = coll.snapshots and coll.snapshots[tostring(id)]
  if not snap then return false end
  snap.name = nm
  return deps.store.save(id, snap)
end

-- SNAP-04: empty the members but KEEP the snapshot (name/fade survive), then
-- persist. Unknown id → false, NO write.
function Manager.clear(deps, id)
  local coll = deps.store.load()
  local snap = coll.snapshots and coll.snapshots[tostring(id)]
  if not snap then return false end
  snap.members = {}
  return deps.store.save(id, snap)
end

-- UI-02 / RCL-03: set the snapshot's DEFAULT fade (seconds) — the value used when a
-- recall arg omits `fade=`. Mirrors rename: mutate the ONE field only, then persist
-- via the peer-safe per-id delta. tonumber-coerce; reject non-numeric or negative
-- (no write, false); 0 is VALID (instant/snap). Unknown id → false, NO write.
function Manager.set_default_fade(deps, id, seconds)
  local n = tonumber(seconds)
  if not n or n < 0 then return false end
  local coll = deps.store.load()
  local snap = coll.snapshots and coll.snapshots[tostring(id)]
  if not snap then return false end
  snap.fade = n
  return deps.store.save(id, snap)
end

-- SNAP-05: drop the id (store.delete merges out only this id). Returns store's result.
function Manager.delete(deps, id)
  return deps.store.delete(id)
end

-- Duplicate a snapshot: fresh id → an INDEPENDENT deep copy of the source's members + fade, name
-- suffixed " copy". Unknown id → nil, NO write. Each member's ref is copied field-by-field so the
-- new snapshot never shares tables with the source. Returns the new id (or nil).
function Manager.duplicate(deps, id)
  local coll = deps.store.load()
  local src  = coll.snapshots and coll.snapshots[tostring(id)]
  if not src then return nil end
  local newid = (deps.new_id or Snapshots.dispatch.next_free_id)(coll.snapshots or {})
  local snap  = deps.model.new_snapshot((src.name or "Snapshot") .. " copy")
  snap.fade   = src.fade or 0
  local members = {}
  for _, m in ipairs(src.members or {}) do
    local ref = {}
    for k, v in pairs(m.ref or {}) do ref[k] = v end   -- copy scalar ref fields (no shared tables)
    members[#members + 1] = { ref = ref, assigned = m.assigned, value = m.value }
  end
  snap.members = members
  return deps.store.save(newid, snap) and newid or nil
end

-- SNAP-02: PURE, deterministic id-sorted rows with badge counts. Each row is
-- {id, name, sub_line, assigned, stored}: stored = #members, assigned = count of
-- assigned members. sub_line defaults "" — the model has no song field yet (A1).
-- nil/{} coll → empty list (finite guarded walk; no crash — T-07-04).
function Manager.list_rows(coll)
  local rows = {}
  for id, snap in pairs((coll and coll.snapshots) or {}) do
    local assigned, stored = 0, 0
    for _, m in ipairs(snap.members or {}) do
      stored = stored + 1
      if m.assigned then assigned = assigned + 1 end
    end
    rows[#rows + 1] = { id = id, name = snap.name, sub_line = snap.song or "",
                        assigned = assigned, stored = stored }
  end
  table.sort(rows, function(a, b) return (tonumber(a.id) or 0) < (tonumber(b.id) or 0) end)
  return rows
end

Snapshots.manager = Manager   -- attach under the namespace key
return Manager                -- RETURN THE TABLE (tests dofile it for this value)
