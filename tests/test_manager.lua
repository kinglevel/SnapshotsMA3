-- tests/test_manager.lua — the pure, store-injected snapshot LIFECYCLE
-- (SNAP-01 create / SNAP-03 rename / SNAP-04 clear / SNAP-05 delete) plus the
-- pure snapshot-list VIEW-MODEL (SNAP-02 list_rows). manager is where the console
-- GUI's substance is proven off-desk: the ScreenOverlay render (Plan 03) is a thin
-- adapter that holds ZERO lifecycle logic, so this suite is the honest proof.
--
-- Test strategy (mirror test_dispatch.lua): manager touches NO MA3 global, so the
-- unit blocks use a PLAIN SPY store table (NOT withGlobalVarsMock — that installs
-- console globals manager must never see). Only the end-to-end round-trip block
-- opts into withGlobalVarsMock + the REAL store.lua to prove peer-safe persistence.
-- No process-exit here (Pitfall 8 — run_all owns the single suite exit).
local h = dofile((debug.getinfo(1,"S").source:sub(2):match("(.*/)") or "./") .. "helpers.lua")

-- Pure collaborators the manager composes; they attach to the Snapshots.* namespace.
h.loadModule("num.lua")
h.loadModule("schema.lua")
h.loadModule("model.lua")
h.loadModule("dispatch.lua")

-- Build a spy `deps` bag over a seeded snapshots map. store is a hand-rolled spy
-- that RECORDS its calls; model + new_id are the REAL collaborators.
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

-- SNAP-01 — create: fresh deterministic id → empty named snapshot → persist just
-- that id. Empty/whitespace/nil name rejected (no write). Duplicates allowed (A3).
h.run("manager SNAP-01: create id'd empty snapshot; reject blank; allow duplicates (A3)", function()
  local M = h.loadModule("manager.lua")

  -- create on an empty collection → id "1", empty snapshot, saved.
  do
    local deps, calls = newDeps({})
    local id = M.create(deps, "Verse")
    h.assertEq(id, "1", "create returns the first free id '1'")
    h.assertTrue(calls.save ~= nil, "create writes the snapshot (store.save called)")
    h.assertEq(calls.save.id, "1", "create saves under id '1'")
    h.assertEq(calls.save.snap.name, "Verse", "created snapshot carries the name")
    h.assertEq(calls.save.snap.fade, 0, "created snapshot fade defaults to 0")
    h.assertEq(#calls.save.snap.members, 0, "created snapshot is EMPTY (members assigned later)")
  end

  -- whitespace-only name rejected: nil return, NO write.
  do
    local deps, calls = newDeps({})
    h.assertNil(M.create(deps, "  "), "whitespace name returns nil")
    h.assertNil(calls.save, "whitespace name never writes")
  end

  -- empty-string name rejected.
  do
    local deps, calls = newDeps({})
    h.assertNil(M.create(deps, ""), "empty name returns nil")
    h.assertNil(calls.save, "empty name never writes")
  end

  -- nil name rejected.
  do
    local deps, calls = newDeps({})
    h.assertNil(M.create(deps, nil), "nil name returns nil")
    h.assertNil(calls.save, "nil name never writes")
  end

  -- A3: a duplicate name is ALLOWED — snapshots are id-keyed; saves under next id.
  do
    local deps, calls = newDeps({ ["1"] = { name = "Verse", fade = 0, members = {} } })
    local id = M.create(deps, "Verse")
    h.assertEq(id, "2", "duplicate name still creates (A3), under the next free id '2'")
    h.assertEq(calls.save.id, "2", "duplicate saves under id '2'")
    h.assertEq(calls.save.snap.name, "Verse", "duplicate name is stored verbatim (no collision guard)")
  end
end)

-- SNAP-03 — rename: mutate name ONLY; members/fade untouched; same id saved.
-- Empty new name and unknown id both rejected (no write).
h.run("manager SNAP-03: rename mutates only the name; reject blank/unknown", function()
  local M = h.loadModule("manager.lua")

  local function seed()
    return { ["4"] = { name = "Old", fade = 3,
      members = { { ref = { guid = "G" }, assigned = true, value = 50 } } } }
  end

  -- happy path: name changes, id/fade/members preserved.
  do
    local deps, calls = newDeps(seed())
    local ok = M.rename(deps, "4", "New")
    h.assertTrue(ok, "rename returns truthy on success")
    h.assertEq(calls.save.id, "4", "rename saves under the same id '4'")
    h.assertEq(calls.save.snap.name, "New", "rename changes the name")
    h.assertEq(calls.save.snap.fade, 3, "rename leaves fade untouched")
    h.assertEq(#calls.save.snap.members, 1, "rename leaves members untouched")
  end

  -- blank new name rejected.
  do
    local deps, calls = newDeps(seed())
    h.assertEq(M.rename(deps, "4", "  "), false, "blank new name returns false")
    h.assertNil(calls.save, "blank new name never writes")
  end

  -- unknown id rejected.
  do
    local deps, calls = newDeps(seed())
    h.assertEq(M.rename(deps, "99", "X"), false, "unknown id returns false")
    h.assertNil(calls.save, "unknown id never writes")
  end
end)

-- UI-02 — set_default_fade: mutate ONLY snap.fade (name/members untouched); same
-- id saved. Non-numeric / negative seconds and unknown id all rejected (NO write);
-- 0 is a valid default (instant/snap recall). Mirrors rename's deps-first shape.
h.run("manager set_default_fade: mutate only snap.fade + save; reject bad", function()
  local M = h.loadModule("manager.lua")

  local function seed()
    return { ["4"] = { name = "Verse", fade = 3, members = {
      { ref = { guid = "G" }, assigned = true,  value = 50 },
      { ref = { guid = "H" }, assigned = false, value = 70 },
    } } }
  end

  -- happy path: fade changes to 6; id/name/members preserved.
  do
    local deps, calls = newDeps(seed())
    local ok = M.set_default_fade(deps, "4", 6)
    h.assertTrue(ok, "set_default_fade returns truthy on success")
    h.assertEq(calls.save.id, "4", "set_default_fade saves under the same id '4'")
    h.assertEq(calls.save.snap.fade, 6, "set_default_fade sets fade to 6")
    h.assertEq(calls.save.snap.name, "Verse", "set_default_fade leaves the name untouched")
    h.assertEq(#calls.save.snap.members, 2, "set_default_fade leaves members untouched")
  end

  -- 0 is a VALID default fade (instant/snap recall).
  do
    local deps, calls = newDeps(seed())
    local ok = M.set_default_fade(deps, "4", 0)
    h.assertTrue(ok, "fade 0 is valid → returns truthy")
    h.assertEq(calls.save.snap.fade, 0, "fade 0 is written verbatim")
  end

  -- id accepted as a number too (tostring(id) indexing, mirroring rename).
  do
    local deps, calls = newDeps(seed())
    local ok = M.set_default_fade(deps, 4, 2)
    h.assertTrue(ok, "numeric id resolves via tostring(id)")
    h.assertEq(calls.save.snap.fade, 2, "numeric id sets fade to 2")
  end

  -- unknown id rejected: false, NO write.
  do
    local deps, calls = newDeps(seed())
    h.assertEq(M.set_default_fade(deps, "99", 6), false, "unknown id returns false")
    h.assertNil(calls.save, "unknown id never writes")
  end

  -- non-numeric seconds rejected: false, NO write.
  do
    local deps, calls = newDeps(seed())
    h.assertEq(M.set_default_fade(deps, "4", "abc"), false, "non-numeric seconds returns false")
    h.assertNil(calls.save, "non-numeric seconds never writes")
  end

  -- negative seconds rejected: false, NO write.
  do
    local deps, calls = newDeps(seed())
    h.assertEq(M.set_default_fade(deps, "4", -1), false, "negative seconds returns false")
    h.assertNil(calls.save, "negative seconds never writes")
  end
end)

-- SNAP-04 — clear: empty the members but KEEP the snapshot (name/fade survive).
-- Same id saved; unknown id rejected.
h.run("manager SNAP-04: clear empties members, keeps name/fade; reject unknown", function()
  local M = h.loadModule("manager.lua")

  local function seed()
    return { ["2"] = { name = "Chorus", fade = 5, members = {
      { ref = { guid = "A" }, assigned = true,  value = 40 },
      { ref = { guid = "B" }, assigned = false, value = 70 },
    } } }
  end

  do
    local deps, calls = newDeps(seed())
    local ok = M.clear(deps, "2")
    h.assertTrue(ok, "clear returns truthy on success")
    h.assertEq(calls.save.id, "2", "clear saves under the same id '2'")
    h.assertEq(#calls.save.snap.members, 0, "clear empties the members")
    h.assertEq(calls.save.snap.name, "Chorus", "clear KEEPS the snapshot name")
    h.assertEq(calls.save.snap.fade, 5, "clear KEEPS the snapshot fade")
  end

  do
    local deps, calls = newDeps(seed())
    h.assertEq(M.clear(deps, "99"), false, "clear of an unknown id returns false")
    h.assertNil(calls.save, "clear of an unknown id never writes")
  end
end)

-- SNAP-05 — delete: passes the id straight to store.delete and returns its result.
h.run("manager SNAP-05: delete calls store.delete(id) and returns its result", function()
  local M = h.loadModule("manager.lua")
  local deps, calls = newDeps({ ["2"] = { name = "Bridge", fade = 0, members = {} } })
  local ok = M.delete(deps, "2")
  h.assertEq(calls.delete, "2", "delete passes the id to store.delete")
  h.assertEq(ok, true, "delete returns store.delete's result")
end)

h.run("manager duplicate: deep-copies members+fade under a fresh id, name +' copy'", function()
  local M = h.loadModule("manager.lua")
  local src = { name = "Verse", fade = 3, members = {
    { ref = Snapshots.schema.new_ref{ guid = "G1", type = "group" }, assigned = true,  value = 55 },
    { ref = Snapshots.schema.new_ref{ guid = "G2", type = "group" }, assigned = false, value = 20 },
  } }
  local deps, calls = newDeps({ ["1"] = src })
  local newid = M.duplicate(deps, "1")
  h.assertEq(newid, "2", "duplicate gets the next free id")
  h.assertEq(calls.save.snap.name, "Verse copy", "name suffixed ' copy'")
  h.assertEq(calls.save.snap.fade, 3, "fade copied")
  h.assertEq(#calls.save.snap.members, 2, "both members copied")
  h.assertEq(calls.save.snap.members[1].value, 55, "member value copied")
  h.assertEq(calls.save.snap.members[2].assigned, false, "parked member copied")
  calls.save.snap.members[1].ref.guid = "X"                 -- mutate the copy
  h.assertEq(src.members[1].ref.guid, "G1", "copy is INDEPENDENT (no shared ref table)")

  local deps2, calls2 = newDeps({})
  h.assertNil(M.duplicate(deps2, "99"), "unknown id → nil")
  h.assertNil(calls2.save, "unknown id → no write")
end)

-- SNAP-02 — list_rows: PURE (pass a coll directly, no deps). id-sorted rows with
-- {id,name,sub_line,assigned,stored}; badge counts; blank sub_line (A1); nil/{} safe.
h.run("manager SNAP-02: id-sorted view-model rows with badge counts; blank sub_line (A1)", function()
  local M = h.loadModule("manager.lua")

  local coll = { version = 1, snapshots = {
    ["2"] = { name = "Bridge", fade = 0, members = {
      { ref = { guid = "X" }, assigned = false, value = 0 } } },
    ["1"] = { name = "Verse", fade = 0, members = {
      { ref = { guid = "A" }, assigned = true,  value = 50 },
      { ref = { guid = "B" }, assigned = true,  value = 60 },
      { ref = { guid = "C" }, assigned = false, value = 0 } } },
  } }
  local rows = M.list_rows(coll)
  h.assertEq(#rows, 2, "list_rows returns one row per snapshot")
  h.assertEq(rows[1].id, "1", "rows are id-sorted ascending → '1' first")
  h.assertEq(rows[2].id, "2", "rows are id-sorted ascending → '2' second")
  h.assertEq(rows[1].assigned, 2, "row '1' assigned badge counts the 2 assigned members")
  h.assertEq(rows[1].stored, 3, "row '1' stored badge counts all 3 members")
  h.assertEq(rows[2].assigned, 0, "row '2' has 0 assigned")
  h.assertEq(rows[2].stored, 1, "row '2' has 1 stored member")
  h.assertEq(rows[2].name, "Bridge", "row '2' carries its name")
  h.assertEq(rows[1].sub_line, "", "sub_line is blank — no song source field yet (A1)")

  -- empty / nil / {} all yield an empty list without crashing (T-07-04).
  h.assertEq(#M.list_rows({ version = 1, snapshots = {} }), 0, "empty coll → empty list")
  h.assertEq(#M.list_rows(nil), 0, "list_rows(nil) → empty list (no crash)")
  h.assertEq(#M.list_rows({}), 0, "list_rows({}) → empty list (no crash)")
end)

-- END-TO-END — the REAL store round-trip via withGlobalVarsMock. Proves the whole
-- create→rename→clear→delete pipeline persists peer-safely through store.lua.
h.run("manager end-to-end: create/rename/clear/delete persist through the real store", function()
  local M = h.loadModule("manager.lua")
  h.loadModule("store.lua")

  h.withGlobalVarsMock(nil, function()
    local deps = {
      model  = Snapshots.model,
      new_id = Snapshots.dispatch.next_free_id,
      store  = Snapshots.store,
    }

    -- create two snapshots → the reload shows both (2 rows).
    local idA = M.create(deps, "A")
    local idB = M.create(deps, "B")
    h.assertTrue(idA ~= nil and idB ~= nil, "both creates returned ids")
    h.assertEq(#M.list_rows(Snapshots.store.load()), 2, "both snapshots persisted (2 rows)")

    -- rename A → the reload shows the new name and B unchanged (peer-safe merge).
    h.assertTrue(M.rename(deps, idA, "A2"), "rename A persisted")
    do
      local snaps = Snapshots.store.load().snapshots
      h.assertEq(snaps[tostring(idA)].name, "A2", "A's new name survived the round-trip")
      h.assertEq(snaps[tostring(idB)].name, "B", "peer B untouched by A's rename")
    end

    -- clear A2 → still 2 rows (the snapshot survives, only members drop).
    h.assertTrue(M.clear(deps, idA), "clear A2 persisted")
    h.assertEq(#M.list_rows(Snapshots.store.load()), 2, "clear keeps the snapshot (still 2 rows)")

    -- delete B → the reload shows 1 row (only A2 remains).
    h.assertTrue(M.delete(deps, idB), "delete B persisted")
    local rows = M.list_rows(Snapshots.store.load())
    h.assertEq(#rows, 1, "after deleting B, only 1 row remains")
    h.assertEq(rows[1].name, "A2", "the surviving row is A2")
  end)
end)
