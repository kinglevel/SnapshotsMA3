-- lib/assign.lua (Snapshots.assign) — the PURE tick/park data-model transforms
-- (ASGN-01 assign / ASGN-02 park + the assign_many bulk primitive) and the two
-- pane VIEW-MODELS (type_rows for pane 2, object_rows for pane 3). This is where
-- assign-only semantics are PROVEN off-console; the Wave-3 console UI is a thin
-- adapter that holds ZERO assignment logic (every tick handler is a one-line
-- Snapshots.assign.* call, then the UI persists via the INJECTED store).
--
-- ASSIGN-ONLY SEMANTICS (08-CONTEXT, LOCKED):
--   * tick   = membership with a PLACEHOLDER value 0 (values come from an explicit
--              Store, NEVER captured on tick).
--   * re-tick of a parked member KEEPS its stored value (the ONLY subtlety —
--              model.set_member overwrites value unconditionally, so assign must
--              PRE-READ the existing member's value; Pitfall 3).
--   * untick = park: assigned=false, value KEPT, excluded from recall_plan; park
--              NEVER creates a ghost on a non-member.
--
-- BOUNDARY DISCIPLINE (D-06): assign reaches NO MA3 console global
-- and NEVER persists — writing the blob is the UI handler's job in Wave 3
-- (the store collaborator is injected there). Reuses model.set_member VERBATIM (no
-- re-implemented dedup) and Snapshots.schema.key for identity — both resolved at
-- CALL time inside function bodies, NEVER captured as file-scope upvalues (sibling
-- load order isn't guaranteed — SHARED-B / Pitfall 3).
Snapshots = Snapshots or {}   -- idempotent bootstrap (NEVER `= {}` — wipes siblings)
local Assign = {}

-- Find a member of snap by ref identity (schema.key, GUID-first). Returns the
-- member table or nil. Guarded walk so a nil/empty snap never crashes (T-07-04).
local function find_member(snap, ref)
  local key = Snapshots.schema.key(ref)                 -- call-time cross-ref
  for _, m in ipairs((snap and snap.members) or {}) do
    if Snapshots.schema.key(m.ref) == key then return m end
  end
  return nil
end

-- ASGN-01: tick a ref into membership. PRE-READ the existing value so a re-tick of a parked member
-- keeps its stored value; a brand-new ref takes `capture_value` (the live console value passed by
-- the UI) so ticking an object with no prior value stores its CURRENT value — or 0 if none given.
function Assign.assign(snap, ref, capture_value)
  local existing = find_member(snap, ref)
  local value = existing and existing.value or capture_value or 0
  return Snapshots.model.set_member(snap, ref, true, value)
end

-- ASGN-02: untick (park) a member — assigned=false, value KEPT so a later re-tick
-- restores it. NO-OP on a non-member (returns nil, never creates a parked ghost).
function Assign.park(snap, ref)
  local existing = find_member(snap, ref)
  if not existing then return nil end                   -- park never ghosts a non-member
  return Snapshots.model.set_member(snap, ref, false, existing.value)
end

-- Bulk primitive for the populate paths (ASGN-04/05/06): assign each ref; dedup is
-- inherited from assign/set_member (a repeated ref updates in place, no duplicate).
function Assign.assign_many(snap, refs)
  for _, ref in ipairs(refs or {}) do Assign.assign(snap, ref) end
  return snap
end

-- ── PANE VIEW-MODELS (mirror manager.list_rows purity: nil/{}-guarded, deterministic) ──

-- Bucket an object type into one of the FIVE pane-2 categories. Each stored member type
-- maps to its own category; a fader assignment (typed "executor" — a VIEW of what's on the
-- executor faders) and any legacy/unknown type fall under "Executor masters".
local function cat_of(t)
  if t == "group" then return "group"
  elseif t == "master" then return "master"
  elseif t == "sequence" then return "sequence"
  elseif t == "preset" then return "preset"
  else return "executor" end
end

-- The 5 pane-2 category rows, in a FIXED display order with their headings.
local CATEGORIES = {
  { category = "executor", label = "Executor masters" },
  { category = "sequence", label = "Sequences"        },
  { category = "preset",   label = "Presets"          },
  { category = "group",    label = "Group masters"    },
  { category = "master",   label = "Special masters"  },
}

-- type_rows (pane 2 view-model): exactly 3 rows {category, label, in_show, assigned}.
-- in_show = the live pool count for that category (pool_counts[category] or 0);
-- assigned = the count of ASSIGNED members whose cat_of(type) falls in the category
-- (parked members are excluded — only assigned==true is counted). Deterministic;
-- nil pool_counts / nil snap → zeroed rows, no crash (T-07-04).
-- `pools` (optional) = { executor=refs, group=refs, sequence=refs, preset=refs, master=refs }
-- from pool_objects(). Each assigned member is categorised by its GUID's LIVE POOL membership
-- (the source of truth — the stored member.type can be stale, e.g. ticked before a re-type), and
-- additionally counts in "Executor masters" if its GUID is on a fader. So a group-on-a-fader counts
-- as BOTH a Group master and an Executor master (shows in both panes) but is ONE member. Falls back
-- to the stored type when a GUID is in no pool (a deleted/missing object).
function Assign.type_rows(pool_counts, snap, pools)
  pool_counts = pool_counts or {}
  pools = pools or {}
  local realcat, onFader = {}, {}
  for _, cat in ipairs({ "group", "sequence", "preset", "master" }) do
    for _, r in ipairs(pools[cat] or {}) do realcat[Snapshots.schema.key(r)] = cat end
  end
  for _, r in ipairs(pools.executor or {}) do onFader[Snapshots.schema.key(r)] = true end
  local assigned = { executor = 0, sequence = 0, preset = 0, group = 0, master = 0 }
  for _, m in ipairs((snap and snap.members) or {}) do
    if m.assigned then
      local key = Snapshots.schema.key(m.ref)
      local c = realcat[key] or cat_of(m.ref.type)   -- live pool wins; stored type is the fallback
      if c ~= "executor" then assigned[c] = (assigned[c] or 0) + 1 end   -- its real-type pane
      if onFader[key] or c == "executor" then                           -- + the fader finder view
        assigned.executor = assigned.executor + 1
      end
    end
  end
  local rows = {}
  for _, spec in ipairs(CATEGORIES) do
    rows[#rows + 1] = {
      category = spec.category,
      label    = spec.label,
      in_show  = pool_counts[spec.category] or 0,
      assigned = assigned[spec.category],
    }
  end
  return rows
end

-- object_rows (pane 3 view-model): one row per pool object with a derived tick-state,
-- THEN the members not present in the pool appended as "missing". A row is
-- {key, label, addr, type, state, ticked, value}:
--   member & assigned → state="assigned", ticked=true,  value=m.value
--   member & parked   → state="parked",   ticked=false, value=m.value  (value kept)
--   not a member      → state="unassigned",ticked=false, value=nil
--   member off-pool   → state="missing",  ticked=(m.assigned), value=m.value
-- Membership is matched by schema.key (GUID-first, call time). NEVER load()s data;
-- reads only plain schema fields (T-08-03). nil/{}-guarded (no crash).
-- `category` (optional) scopes the "missing" append to members of THIS pane's category
-- (cat_of(member.type) == category). Without it a group member showed as "Missing?" under the
-- Executor pane and vice-versa (onPC feedback). nil category → append all (back-compat).
-- `no_missing` (optional) suppresses the missing-member append entirely — used when a specific
-- datapool is selected, so a member living in ANOTHER datapool is not shown as "Missing" (it's
-- just not in the chosen datapool). Without a datapool filter, missing rows are still appended.
function Assign.object_rows(pool_objs, snap, category, no_missing)
  local members = {}
  for _, m in ipairs((snap and snap.members) or {}) do
    members[Snapshots.schema.key(m.ref)] = m           -- call-time cross-ref
  end
  local rows, seen = {}, {}
  for _, obj in ipairs(pool_objs or {}) do
    local key = Snapshots.schema.key(obj)
    seen[key] = true
    local m = members[key]
    local state, ticked, value
    if m then
      if m.assigned then state, ticked, value = "assigned", true, m.value
      else               state, ticked, value = "parked",  false, m.value end
    else
      state, ticked, value = "unassigned", false, nil
    end
    rows[#rows + 1] = { key = key, label = obj.label, addr = obj.addr, type = obj.type,
                        state = state, ticked = ticked, value = value }
  end
  -- append the members with no live pool object as benign "missing" rows — but ONLY those
  -- belonging to this pane's category (a group member is not "missing" under the Sequence pane),
  -- and NOT at all when a datapool filter is active (other-datapool members aren't "missing").
  for _, m in ipairs((no_missing and {}) or (snap and snap.members) or {}) do
    local key = Snapshots.schema.key(m.ref)
    if not seen[key] and (category == nil or cat_of(m.ref.type) == category) then
      rows[#rows + 1] = { key = key, label = m.ref.label, addr = m.ref.addr, type = m.ref.type,
                          state = "missing", ticked = (m.assigned and true or false), value = m.value }
    end
  end
  return rows
end

Snapshots.assign = Assign   -- attach under the namespace key
return Assign               -- RETURN THE TABLE (tests dofile it for this value)
