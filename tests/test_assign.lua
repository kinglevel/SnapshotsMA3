-- tests/test_assign.lua — the pure, host-tested tick/park data-model transforms
-- (ASGN-01 assign / ASGN-02 park / assign_many) plus the two pane VIEW-MODELS
-- (type_rows for pane 2, object_rows for pane 3). assign is where the recall
-- filter's SUBSTANCE is proven off-console — the Wave-3 console UI is a thin
-- adapter over these functions and holds ZERO assignment logic.
--
-- Test strategy (mirror test_manager.lua): assign touches NO MA3 global, so the
-- blocks use PLAIN tables + a spy store (NOT any GlobalVars mock — assign must
-- never see console globals). The store is injected at the UI layer; assign.lua
-- itself NEVER calls store.save (boundary D-06). No process-exit
-- here (run_all owns the single suite exit — Pitfall 8).
local h = dofile((debug.getinfo(1,"S").source:sub(2):match("(.*/)") or "./") .. "helpers.lua")

-- Pure collaborators assign composes; they attach to the Snapshots.* namespace.
h.loadModule("num.lua")
h.loadModule("schema.lua")
h.loadModule("model.lua")
h.loadModule("dispatch.lua")

-- Spy `deps` bag mirroring test_manager.lua:22-34 — store RECORDS its calls so the
-- toggle→persist path (the UI handler's job in Wave 3) can be asserted; model +
-- new_id are the REAL collaborators. assign.lua itself does NOT touch this store.
local function newDeps(snapshots)
  local calls = {}
  local deps = {
    model  = Snapshots.model,
    new_id = Snapshots.dispatch.next_free_id,
    store  = {
      load   = function() calls.load = true; return { version = 1, snapshots = snapshots or {} } end,
      save   = function(id, snap) calls.save = { id = id, snap = snap }; return true end,
      delete = function(id) calls.delete = id; return true end,
    },
  }
  return deps, calls
end

-- Small ref builders (validated via schema.new_ref) for the fixture snapshots.
local function gref(guid, t) return Snapshots.schema.new_ref{ guid = guid, type = t or "group" } end
local function eref(addr)    return Snapshots.schema.new_ref{ addr = addr, type = "executor" } end

-- ASGN-01 — assign = MEMBERSHIP with a placeholder value 0. The tick never
-- captures a live value; values come from an explicit Store. Re-ticking a parked
-- member must KEEP its stored value (Pitfall 3: set_member overwrites value, so
-- assign MUST pre-read the existing value). assign dedups by schema.key.
h.run("assign ASGN-01: brand-new ref, no capture value → placeholder 0", function()
  local A = h.loadModule("assign.lua")
  local snap = Snapshots.model.new_snapshot("Verse")
  A.assign(snap, gref("G1"))
  h.assertEq(#snap.members, 1, "assign creates exactly one member")
  h.assertEq(snap.members[1].assigned, true, "the member is assigned")
  h.assertEq(snap.members[1].value, 0, "value is the placeholder 0 when no capture value given")
end)

h.run("assign: brand-new ref WITH a capture value → stores that current value", function()
  local A = h.loadModule("assign.lua")
  local snap = Snapshots.model.new_snapshot("Verse")
  A.assign(snap, gref("G1"), 62)                          -- ticking captures the live value
  h.assertEq(snap.members[1].value, 62, "new member stores the captured current value, not 0")
  -- a re-tick of a PARKED member ignores the capture value and keeps its stored value
  A.park(snap, gref("G1"))
  A.assign(snap, gref("G1"), 99)
  h.assertEq(snap.members[1].value, 62, "re-tick keeps the stored value; capture value ignored")
end)

h.run("assign ASGN-01: re-tick a PARKED member keeps its value (never reset to 0)", function()
  local A = h.loadModule("assign.lua")
  local snap = Snapshots.model.new_snapshot("Verse")
  local ref = gref("G1")
  A.assign(snap, ref)                                   -- placeholder value 0
  Snapshots.model.set_member(snap, ref, true, 75)       -- an explicit Store sets value 75
  A.park(snap, ref)                                     -- untick → parked, value 75 kept
  A.assign(snap, ref)                                   -- re-tick → value MUST stay 75
  h.assertEq(#snap.members, 1, "still one member (dedup through park/re-assign)")
  h.assertEq(snap.members[1].assigned, true, "re-ticked back to assigned")
  h.assertEq(snap.members[1].value, 75, "value preserved through park → re-assign (not 0)")
end)

h.run("assign: assign twice on the same ref → exactly one member (dedup by schema.key)", function()
  local A = h.loadModule("assign.lua")
  local snap = Snapshots.model.new_snapshot("V")
  local ref = gref("G1")
  A.assign(snap, ref)
  A.assign(snap, ref)
  h.assertEq(#snap.members, 1, "no duplicate member for the same object")
end)

-- ASGN-02 — park = untick: assigned=false, value KEPT (so a re-tick restores it),
-- and NEVER a ghost on a non-member. A parked member is structurally excluded
-- from recall_plan (Phase-3 filter, unchanged).
h.run("park ASGN-02: park an assigned member → assigned=false, value kept", function()
  local A = h.loadModule("assign.lua")
  local snap = Snapshots.model.new_snapshot("V")
  local ref = gref("G1")
  Snapshots.model.set_member(snap, ref, true, 60)
  local m = A.park(snap, ref)
  h.assertTrue(m ~= nil, "park returns the parked member")
  h.assertEq(snap.members[1].assigned, false, "park sets assigned=false")
  h.assertEq(snap.members[1].value, 60, "park KEEPS the stored value")
end)

h.run("park ASGN-02: park on a NON-member → nil AND no ghost member", function()
  local A = h.loadModule("assign.lua")
  local snap = Snapshots.model.new_snapshot("V")
  h.assertNil(A.park(snap, gref("G1")), "park on a non-member returns nil")
  h.assertEq(#snap.members, 0, "park never creates a parked ghost")
end)

h.run("park ASGN-02: a parked member is excluded from model.recall_plan", function()
  local A = h.loadModule("assign.lua")
  local snap = Snapshots.model.new_snapshot("V")
  Snapshots.model.set_member(snap, gref("A"), true, 50)
  Snapshots.model.set_member(snap, gref("B"), true, 60)
  A.park(snap, gref("B"))
  local plan = Snapshots.model.recall_plan(snap)
  h.assertEq(#plan, 1, "only the assigned member is in the recall plan")
  h.assertEq(plan[1].ref.guid, "A", "the parked member B is excluded from recall")
end)

-- assign_many — the bulk primitive the populate paths (ASGN-04/05/06) reuse.
h.run("assign_many: bulk-assigns each ref and dedups", function()
  local A = h.loadModule("assign.lua")
  local snap = Snapshots.model.new_snapshot("V")
  local refA, refB = gref("A"), gref("B", "master")
  A.assign_many(snap, { refA, refB, refA })
  h.assertEq(#snap.members, 2, "two unique members (refA appearing twice is deduped)")
  h.assertEq(snap.members[1].assigned, true, "first is assigned")
  h.assertEq(snap.members[2].assigned, true, "second is assigned")
end)

-- toggle→persist — assign mutates; the UI-SHAPE handler persists via the INJECTED
-- store (assign.lua NEVER saves itself). Proves the persisted snap is the mutated one.
h.run("assign toggle→persist: the UI-shape handler saves the mutated snap (assign itself never saves)", function()
  local A = h.loadModule("assign.lua")
  local snap = Snapshots.model.new_snapshot("V")
  local deps, calls = newDeps({ ["1"] = snap })
  A.assign(snap, gref("G1"))            -- pure mutation
  deps.store.save("1", snap)            -- the Wave-3 handler's persist step
  h.assertTrue(calls.save ~= nil, "store.save was called by the handler")
  h.assertEq(calls.save.snap, snap, "the persisted snap is the SAME mutated table")
  h.assertEq(calls.save.snap.members[1].assigned, true, "the saved snap carries the assignment")
end)

-- ── PANE VIEW-MODELS (Wave-3 adapters over pure logic) ───────────────────────────

-- type_rows (pane 2): exactly 3 category rows in order executor, group, master.
-- in_show comes from the live pool counts; assigned counts ONLY assigned members
-- bucketed by cat_of (sequence/preset/executor → executor). Parked members do NOT
-- increment the assigned count.
h.run("type_rows: 5 ordered category rows with labels, in_show + assigned counts", function()
  local A = h.loadModule("assign.lua")
  local snap = Snapshots.model.new_snapshot("V")
  Snapshots.model.set_member(snap, Snapshots.schema.new_ref{ addr = "1.201", type = "executor" }, true, 50)
  Snapshots.model.set_member(snap, gref("S1", "sequence"), true, 50)   -- own category now
  Snapshots.model.set_member(snap, gref("P1", "preset"),   true, 50)   -- own category now
  Snapshots.model.set_member(snap, gref("G1", "group"),   true, 50)
  Snapshots.model.set_member(snap, gref("G2", "group"),   false, 50)   -- PARKED — must NOT count
  Snapshots.model.set_member(snap, gref("M1", "master"),  true, 50)
  local rows = A.type_rows({ executor = 10, sequence = 7, preset = 4, group = 5, master = 3 }, snap)
  h.assertEq(#rows, 5, "exactly 5 category rows")
  h.assertEq(rows[1].category, "executor", "row 1 is executor")
  h.assertEq(rows[2].category, "sequence", "row 2 is sequence")
  h.assertEq(rows[3].category, "preset",   "row 3 is preset")
  h.assertEq(rows[4].category, "group",    "row 4 is group")
  h.assertEq(rows[5].category, "master",   "row 5 is master")
  h.assertEq(rows[1].label, "Executor masters", "executor label")
  h.assertEq(rows[2].label, "Sequences",        "sequence label")
  h.assertEq(rows[3].label, "Presets",          "preset label")
  h.assertEq(rows[4].label, "Group masters",    "group label")
  h.assertEq(rows[5].label, "Special masters",  "master label")
  h.assertEq(rows[1].in_show, 10, "executor in_show from pool_counts")
  h.assertEq(rows[2].in_show, 7,  "sequence in_show from pool_counts")
  h.assertEq(rows[3].in_show, 4,  "preset in_show from pool_counts")
  h.assertEq(rows[4].in_show, 5,  "group in_show from pool_counts")
  h.assertEq(rows[5].in_show, 3,  "master in_show from pool_counts")
  h.assertEq(rows[1].assigned, 1, "executor assigned = the addr executor")
  h.assertEq(rows[2].assigned, 1, "sequence assigned = S1")
  h.assertEq(rows[3].assigned, 1, "preset assigned = P1")
  h.assertEq(rows[4].assigned, 1, "group assigned = 1 (parked G2 excluded)")
  h.assertEq(rows[5].assigned, 1, "master assigned = 1")
end)

h.run("type_rows: a group ON a fader counts as BOTH group + executor (one member, two panes)", function()
  local A = h.loadModule("assign.lua")
  local snap = Snapshots.model.new_snapshot("V")
  -- both members are stored with a WRONG type ("executor") — the live pools must still
  -- categorise them as groups (robust to stale stored types / old ticks).
  Snapshots.model.set_member(snap, gref("G1", "executor"), true, 50)
  Snapshots.model.set_member(snap, gref("G2", "executor"), true, 50)
  local pools = {
    group    = { gref("G1", "group"), gref("G2", "group") },  -- both are really groups
    executor = { gref("G1", "group") },                       -- only G1 is on a fader
  }
  local rows = A.type_rows({}, snap, pools)
  local byCat = {}; for _, r in ipairs(rows) do byCat[r.category] = r end
  h.assertEq(byCat.group.assigned,    2, "both count as Group masters (by live pool, not stored type)")
  h.assertEq(byCat.executor.assigned, 1, "only the on-fader group also counts as an Executor master")
end)

h.run("type_rows: nil pool_counts and nil snap → 5 zeroed rows, no crash", function()
  local A = h.loadModule("assign.lua")
  local rows = A.type_rows(nil, nil)
  h.assertEq(#rows, 5, "still 5 category rows")
  h.assertEq(rows[1].in_show, 0,  "in_show defaults to 0")
  h.assertEq(rows[1].assigned, 0, "assigned is 0 on a nil snap")
end)

-- object_rows (pane 3): one row per pool object with derived tick-state, PLUS the
-- members that no longer appear in the pool appended as "missing".
h.run("object_rows: assigned/parked/unassigned per membership + appended missing", function()
  local A = h.loadModule("assign.lua")
  local snap = Snapshots.model.new_snapshot("V")
  local g1 = Snapshots.schema.new_ref{ guid = "G1", type = "group", addr = "Group 1", label = "Front" }
  local g2 = Snapshots.schema.new_ref{ guid = "G2", type = "group", addr = "Group 2", label = "Back" }
  local g3 = Snapshots.schema.new_ref{ guid = "G3", type = "group", addr = "Group 3", label = "Side" }
  local gm = Snapshots.schema.new_ref{ guid = "GM", type = "group", addr = "Group 9", label = "Gone" }
  Snapshots.model.set_member(snap, g1, true,  40)   -- assigned
  Snapshots.model.set_member(snap, g2, false, 70)   -- parked
  Snapshots.model.set_member(snap, gm, true,  90)   -- member NOT in the pool → missing
  local rows = A.object_rows({ g1, g2, g3 }, snap)
  h.assertEq(#rows, 4, "3 pool rows + 1 appended missing row")

  h.assertEq(rows[1].state, "assigned", "g1 is an assigned member")
  h.assertEq(rows[1].ticked, true,      "assigned → ticked")
  h.assertEq(rows[1].value, 40,         "assigned row carries the member value")
  h.assertEq(rows[1].key, "G1",         "row key is schema.key")
  h.assertEq(rows[1].label, "Front",    "row label from the pool object")
  h.assertEq(rows[1].addr, "Group 1",   "row addr from the pool object")
  h.assertEq(rows[1].type, "group",     "row type from the pool object")

  h.assertEq(rows[2].state, "parked",   "g2 is a parked member")
  h.assertEq(rows[2].ticked, false,     "parked → not ticked")
  h.assertEq(rows[2].value, 70,         "parked row KEEPS the member value")

  h.assertEq(rows[3].state, "unassigned", "g3 is not a member")
  h.assertEq(rows[3].ticked, false,       "unassigned → not ticked")
  h.assertNil(rows[3].value,              "unassigned row has no value")

  h.assertEq(rows[4].state, "missing",  "gm is a member with no pool object")
  h.assertEq(rows[4].ticked, true,      "missing+assigned → ticked reflects assigned state")
  h.assertEq(rows[4].value, 90,         "missing row carries the member value")
  h.assertEq(rows[4].key, "GM",         "missing row key from the stored ref")

  -- no_missing (datapool filter active): the off-pool member is NOT appended as "missing"
  local filtered = A.object_rows({ g1, g2, g3 }, snap, nil, true)
  h.assertEq(#filtered, 3, "no_missing → only the 3 pool rows, GM not appended")
  for _, r in ipairs(filtered) do h.assertTrue(r.state ~= "missing", "no missing rows when filtered") end
end)

h.run("object_rows: nil pool_objs / nil snap safe; a member with no pool obj is missing", function()
  local A = h.loadModule("assign.lua")
  h.assertEq(#A.object_rows(nil, nil), 0, "nil pool + nil snap → empty rows (no crash)")
  local snap = Snapshots.model.new_snapshot("V")
  Snapshots.model.set_member(snap, gref("X", "group"), false, 20)   -- parked, no pool obj
  local rows = A.object_rows(nil, snap)
  h.assertEq(#rows, 1, "the member with no pool object → one missing row")
  h.assertEq(rows[1].state, "missing", "no pool obj → missing")
  h.assertEq(rows[1].ticked, false,    "a parked missing member is NOT ticked")
end)
