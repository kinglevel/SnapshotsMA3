-- tests/test_dispatch.lua — the command-surface router (INVK-02/03/04, RCL-03/05/06).
-- Dispatch is the pure, dependency-injected seam Main calls: it composes the
-- already-green collaborators (args/model/fade/breakdown/store/ma3) without
-- re-implementing any of them and reaches NO MA3 global.
--
-- Test strategy (RESEARCH spy-fake, CONTEXT boundary): dispatch touches no MA3
-- global, so we use PLAIN SPY TABLES for store/ma3 (NOT withGlobalVarsMock /
-- withAdapterMock — those install console globals dispatch must never see). The
-- REAL model/fade/breakdown modules are injected so the composition contracts
-- (and the breakdown {ref,to}→{ref,value} shape conversion) are proven end-to-end.
-- No process-exit here (Pitfall 8 — run_all owns it).
local h = dofile((debug.getinfo(1,"S").source:sub(2):match("(.*/)") or "./") .. "helpers.lua")

-- Load the pure collaborators once; they attach to the Snapshots.* namespace.
h.loadModule("num.lua")
h.loadModule("schema.lua")
h.loadModule("args.lua")
h.loadModule("model.lua")
h.loadModule("fade.lua")
h.loadModule("breakdown.lua")

-- Build a spy `deps` bag over a seeded snapshots map. store/ma3 are hand-rolled
-- spies that RECORD their calls; model/fade/breakdown are the REAL modules.
local function newDeps(snapshots)
  local calls = { notes = {} }
  local deps = {
    model     = Snapshots.model,
    fade      = Snapshots.fade,
    breakdown = Snapshots.breakdown,
    store = {
      load = function() calls.load = true; return { version = 1, snapshots = snapshots or {} } end,
      save = function(id, snap) calls.save = { id = id, snap = snap }; return true end,
    },
    ma3 = {
      recall  = function(plan, t) calls.recall = { plan = plan, t = t } end,
      capture = function(refs) calls.capture = refs; return calls._cap_ret or {} end,
    },
    -- Spy console-UI collaborator (07-04 seam): open_manager delegates here so
    -- dispatch stays MA3-free. Records the call count AND the deps bag it received,
    -- proving open() is handed the SAME collaborator bag (single DI seam).
    ui = {
      open = function(d)
        calls.open = (calls.open or 0) + 1
        calls.open_deps = d
      end,
    },
    notify = function(msg) calls.notes[#calls.notes + 1] = tostring(msg) end,
  }
  return deps, calls
end

local function hasNote(calls, needle)
  for _, m in ipairs(calls.notes) do if m:find(needle, 1, true) then return true end end
  return false
end

-- 1. INVK-02/04 + error isolation — empty→manager (lazy read, never write),
--    parse-error echo, and the pcall-to-notify catch of a throwing collaborator.
h.run("dispatch INVK-02/04: empty→manager, whitespace, parse-error echo, isolation", function()
  local D = h.loadModule("dispatch.lua")

  -- INVK-02: empty arg → open_manager delegates to the INJECTED deps.ui.open exactly
  -- once, still lazily reads the store (INVK-02) and NEVER writes. The spy open()
  -- must receive the SAME deps bag (single DI seam).
  do
    local deps, calls = newDeps({})
    D.execute("", deps)
    h.assertEq(calls.open, 1, "empty arg calls deps.ui.open exactly once")
    h.assertEq(calls.open_deps, deps, "ui.open receives the SAME deps bag it was routed through")
    h.assertEq(calls.load, true, "empty arg lazily reads the store")
    h.assertNil(calls.save, "empty arg NEVER writes the store (lazy manager path)")
    h.assertNil(calls.recall, "empty arg never recalls")
  end

  -- INVK-02: whitespace-only arg routes to the manager exactly like the empty arg.
  do
    local deps, calls = newDeps({})
    D.execute("   ", deps)
    h.assertEq(calls.open, 1, "whitespace arg also delegates to deps.ui.open once")
    h.assertEq(calls.load, true, "whitespace arg lazily reads the store (manager path)")
    h.assertNil(calls.save, "whitespace arg NEVER writes the store")
  end

  -- T-07-10 degraded fallback: with NO ui in deps, open_manager must NOT crash — it
  -- guards the nil-index and emits a notify instead (off-desk / load-race safety).
  do
    local deps, calls = newDeps({})
    deps.ui = nil
    local ok = pcall(function() D.execute("", deps) end)
    h.assertTrue(ok, "missing ui degrades gracefully (no nil-index crash)")
    h.assertEq(calls.load, true, "missing-ui path still lazily reads the store")
    h.assertNil(calls.save, "missing-ui path still NEVER writes")
    h.assertTrue(#calls.notes >= 1, "missing ui emits a fallback notify")
  end

  -- INVK-04: unknown verb → args.parse's msg echoed verbatim; no recall; no throw.
  do
    local deps, calls = newDeps({})
    D.execute("bogus X", deps)
    h.assertEq(calls.notes[1], "unknown verb 'bogus'", "parse error msg echoed verbatim to notify")
    h.assertNil(calls.recall, "invalid arg never recalls")
  end

  -- INVK-04: missing snapshot name → args.parse's msg echoed.
  do
    local deps, calls = newDeps({})
    D.execute("recall", deps)
    h.assertEq(calls.notes[1], "missing snapshot name", "missing-name parse error echoed to notify")
  end

  -- Isolation: a collaborator that throws is caught inside execute, reported, never re-thrown.
  do
    local snaps = { ["1"] = { name = "Verse", fade = 0,
      members = { { ref = { guid = "G1", type = "group" }, assigned = true, value = 60 } } } }
    local deps, calls = newDeps(snaps)
    deps.ma3.recall = function() error("boom") end
    local ok = pcall(function() D.execute("recall Verse", deps) end)
    h.assertTrue(ok, "execute swallows a throwing collaborator (never re-raised)")
    h.assertTrue(#calls.notes >= 1, "a caught collaborator error is reported to notify")
  end
end)

-- 2. INVK-03 recall composition + RCL-03 fade override + RCL-05 breakdown shape +
--    name resolution (case-insensitive, 0-miss, >1-ambiguous act-on-none).
h.run("dispatch INVK-03/RCL-03/05: recall compose, fade override, breakdown convert, name resolution", function()
  local D = h.loadModule("dispatch.lua")

  local function verseStore()
    return { ["1"] = { name = "Verse", fade = 2,
      members = { { ref = { guid = "G1", type = "group" }, assigned = true, value = 60 } } } }
  end

  -- INVK-03: recall composes model.recall_plan → ma3.recall with the arg-or-default fade.
  do
    local deps, calls = newDeps(verseStore())
    D.execute("recall Verse", deps)
    h.assertTrue(calls.recall ~= nil, "recall reached ma3.recall")
    h.assertEq(#calls.recall.plan, 1, "recall plan has the single assigned member")
    h.assertEq(calls.recall.plan[1].value, 60, "recall plan carries the stored value 60 as {ref,value}")
    h.assertEq(calls.recall.t, 2, "recall used the snapshot default fade (2)")
  end

  -- RCL-03: a numeric fade= arg overrides the snapshot default.
  do
    local deps, calls = newDeps(verseStore())
    D.execute("recall Verse fade=5", deps)
    h.assertEq(calls.recall.t, 5, "fade=5 overrides the snapshot default (RCL-03)")
  end

  -- RCL-05: breakdown drives every eligible object to 100, converted to {ref,value} (NOT {ref,to}).
  do
    local deps, calls = newDeps(verseStore())
    D.execute("recall Verse breakdown", deps)
    h.assertEq(#calls.recall.plan, 1, "breakdown plan still carries the eligible object")
    h.assertEq(calls.recall.plan[1].value, 100, "breakdown overrides to 100 on the .value key")
    h.assertNil(calls.recall.plan[1].to, "breakdown output converted: .to is dropped (shape fix)")
  end

  -- Case-insensitive: "verse" matches stored "Verse".
  do
    local deps, calls = newDeps(verseStore())
    D.execute("recall verse", deps)
    h.assertTrue(calls.recall ~= nil, "case-insensitive name match fires the recall")
  end

  -- Name miss (0): notify "no snapshot named"; act on nothing.
  do
    local deps, calls = newDeps(verseStore())
    D.execute("recall Nope", deps)
    h.assertTrue(hasNote(calls, "no snapshot named"), "0-match notifies 'no snapshot named'")
    h.assertNil(calls.recall, "0-match acts on nothing (no recall)")
  end

  -- Ambiguous (>1): notify "ambiguous"; act on NONE.
  do
    local dup = { ["1"] = { name = "Dup", fade = 0, members = {} },
                  ["2"] = { name = "Dup", fade = 0, members = {} } }
    local deps, calls = newDeps(dup)
    D.execute("recall Dup", deps)
    h.assertTrue(hasNote(calls, "ambiguous"), ">1-match notifies 'ambiguous'")
    h.assertNil(calls.recall, ">1-match acts on NONE (no recall)")
  end
end)

-- 3. INVK-03 mutation verbs — store re-captures existing members, clear empties
--    (keeping the name), store on a NEW name creates an empty snapshot with a
--    deterministic next-free id. Plus a direct unit test of next_free_id.
local function memberValue(snap, guid)
  for _, m in ipairs(snap.members) do if m.ref.guid == guid then return m.value end end
  return nil
end

h.run("dispatch INVK-03 store/clear + create-on-store + next_free_id (deterministic)", function()
  local D = h.loadModule("dispatch.lua")

  -- INVK-03 store (existing): re-capture live values of the CURRENT members and save.
  do
    local snaps = { ["7"] = { name = "Verse", fade = 0, members = {
      { ref = { guid = "R1", type = "group" }, assigned = true, value = 0 },
      { ref = { guid = "R2", type = "group" }, assigned = true, value = 0 },
    } } }
    local deps, calls = newDeps(snaps)
    calls._cap_ret = { { ref = { guid = "R1", type = "group" }, value = 40 },
                       { ref = { guid = "R2", type = "group" }, value = 70 } }
    D.execute("store Verse", deps)
    h.assertTrue(calls.capture ~= nil, "store captured the existing members' live values")
    h.assertEq(#calls.capture, 2, "capture was handed both member refs")
    h.assertEq(memberValue(calls.save.snap, "R1"), 40, "member R1 re-captured to 40 (ma3.capture→set_member)")
    h.assertEq(memberValue(calls.save.snap, "R2"), 70, "member R2 re-captured to 70")
    h.assertEq(calls.save.id, "7", "store saves under the seeded id")
  end

  -- INVK-03 clear: empty the members but KEEP the named snapshot, then save.
  do
    local snaps = { ["7"] = { name = "Verse", fade = 0, members = {
      { ref = { guid = "R1", type = "group" }, assigned = true, value = 40 },
    } } }
    local deps, calls = newDeps(snaps)
    D.execute("clear Verse", deps)
    h.assertTrue(calls.save ~= nil, "clear saves the emptied snapshot")
    h.assertEq(#calls.save.snap.members, 0, "clear empties the members")
    h.assertEq(calls.save.snap.name, "Verse", "clear KEEPS the snapshot name")
    h.assertNil(calls.recall, "clear never recalls")
  end

  -- Create-on-store (A1, LOCKED): a brand-new name creates an EMPTY snapshot with
  -- the deterministic next-free id; nothing to capture.
  do
    local snaps = { ["1"] = { name = "Existing", fade = 0, members = {} } }
    local deps, calls = newDeps(snaps)
    D.execute("store Brandnew", deps)
    h.assertTrue(calls.save ~= nil, "store on a new name saves a fresh snapshot")
    h.assertEq(calls.save.snap.name, "Brandnew", "created snapshot carries the new name")
    h.assertEq(#calls.save.snap.members, 0, "created snapshot is EMPTY (Phase 8 assigns members)")
    h.assertEq(calls.save.id, "2", "created snapshot uses the next-free id after '1'")
    h.assertNil(calls.capture, "creating an empty snapshot captures nothing")
  end

  -- WR-01: a re-store re-captures VALUES but must NOT un-park a parked
  -- (assigned=false) member — the model's D-10 contract. Guards a Phase-8 regression.
  do
    local snaps = { ["7"] = { name = "Verse", fade = 0, members = {
      { ref = { guid = "A1", type = "group" }, assigned = true,  value = 0 },
      { ref = { guid = "P1", type = "group" }, assigned = false, value = 0 },  -- parked
    } } }
    local deps, calls = newDeps(snaps)
    calls._cap_ret = { { ref = { guid = "A1", type = "group" }, value = 40 },
                       { ref = { guid = "P1", type = "group" }, value = 70 } }
    D.execute("store Verse", deps)
    local function memberAssigned(snap, guid)
      for _, m in ipairs(snap.members) do if m.ref.guid == guid then return m.assigned end end
    end
    h.assertEq(memberAssigned(calls.save.snap, "A1"), true,  "assigned member stays assigned on re-store")
    h.assertEq(memberAssigned(calls.save.snap, "P1"), false, "parked member STAYS parked on re-store (WR-01)")
    h.assertEq(memberValue(calls.save.snap, "P1"), 70, "parked member's stored value still refreshes")
  end

  -- next_free_id determinism (direct unit test — NO random/os.time).
  do
    h.assertEq(D.next_free_id({}), "1", "next_free_id of an empty map is '1'")
    h.assertEq(D.next_free_id({ ["1"] = {}, ["2"] = {} }), "3", "next_free_id fills after '1','2' → '3'")
    h.assertEq(D.next_free_id({ ["2"] = {} }), "1", "next_free_id fills the lowest free integer → '1'")
  end
end)

-- 4. UI-03 arg echo — a non-empty command echoes its trimmed arg string to deps.notify
--    (= Snapshots.log → the System Monitor strip), IN ADDITION to running the intent;
--    the empty/whitespace manager path stays SILENT (no echo). ADDED block: every
--    pre-existing assertion above is untouched (add, not reorder — CONTEXT rule).
h.run("dispatch UI-03: non-empty command echoes its trimmed arg; empty/whitespace path silent", function()
  local D = h.loadModule("dispatch.lua")

  local function verseStore()
    return { ["1"] = { name = "Verse", fade = 2,
      members = { { ref = { guid = "G1", type = "group" }, assigned = true, value = 60 } } } }
  end

  -- a non-empty VALID command echoes its exact trimmed arg AND still runs.
  do
    local deps, calls = newDeps(verseStore())
    D.execute('  recall Verse fade=3  ', deps)                 -- surrounding ws trimmed
    h.assertTrue(hasNote(calls, "recall Verse fade=3"),
      "the trimmed command string was echoed to notify (strip + sysmon, UI-03)")
    h.assertTrue(calls.recall ~= nil, "the command still ran (echo does not replace execution)")
  end

  -- a store command also echoes its arg (every command shows on the strip).
  do
    local snaps = { ["1"] = { name = "Existing", fade = 0, members = {} } }
    local deps, calls = newDeps(snaps)
    D.execute("store Brandnew", deps)
    h.assertTrue(hasNote(calls, "store Brandnew"), "a store command echoes its arg too")
  end

  -- empty arg → manager path, NO echo line on the strip.
  do
    local deps, calls = newDeps({})
    D.execute("", deps)
    h.assertEq(#calls.notes, 0, "empty arg echoes nothing (manager path stays silent)")
  end

  -- whitespace-only arg → manager path, NO echo.
  do
    local deps, calls = newDeps({})
    D.execute("   ", deps)
    h.assertEq(#calls.notes, 0, "whitespace-only arg echoes nothing (manager path silent)")
  end
end)
