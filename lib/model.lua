-- lib/model.lua (Snapshots.model) — the snapshot data model (CAP-04 / RCL-01 /
-- D-09 / D-10). A snapshot is {name, fade(default), members[]}; each member is
-- {ref, assigned:bool, value:0..100}. set_member dedups by schema.key so a ref is
-- stored once (updated in place, never duplicated). Unassigned members are KEPT
-- with assigned=false (D-10) so the UI can re-tick them; recall_plan (RCL-01)
-- filters to assigned==true only, returning {ref,value} — non-members are never
-- touched on recall (T-03-10).
-- PURE module — touches no MA3 global (boundary policy D-06). Cross-refs
-- Snapshots.schema at CALL time (SHARED-B / Pitfall 3), never a file-scope upvalue.
Snapshots = Snapshots or {}   -- idempotent bootstrap (NEVER `= {}` — wipes siblings)
local Model = {}

-- Build an empty snapshot. default_fade is the per-snapshot fallback fade time
-- (an arg on recall overrides it — see fade.resolve_time); omitted → 0.
function Model.new_snapshot(name, default_fade)
  return { name = name, fade = default_fade or 0, members = {} }
end

-- Store a member. Dedups by schema.key (call-time cross-ref): a ref whose key
-- matches an existing member UPDATES it in place (no duplicate); otherwise a new
-- {ref, assigned, value} member is appended. Parked (assigned=false) members are
-- kept, not removed (D-10). Returns the stored member table.
function Model.set_member(snap, ref, assigned, value)
  local key = Snapshots.schema.key(ref)                 -- call-time cross-ref
  for _, m in ipairs(snap.members) do
    if Snapshots.schema.key(m.ref) == key then
      m.assigned = assigned and true or false
      m.value = value
      return m
    end
  end
  local m = { ref = ref, assigned = assigned and true or false, value = value }
  snap.members[#snap.members + 1] = m
  return m
end

-- RCL-01: build the recall plan — assigned==true members only, as {ref,value}.
-- Parked members stay in snap.members but are structurally excluded here, so a
-- recall can never move a non-member (T-03-10).
function Model.recall_plan(snap)
  local plan = {}
  for _, m in ipairs(snap.members) do
    if m.assigned then plan[#plan + 1] = { ref = m.ref, value = m.value } end
  end
  return plan
end

Snapshots.model = Model   -- attach under the namespace key
return Model              -- RETURN THE TABLE (tests dofile it for this value)
