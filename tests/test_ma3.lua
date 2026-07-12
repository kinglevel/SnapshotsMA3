-- tests/test_ma3.lua — the console-adapter READ boundary (OBJ-02 / CAP-01..05).
-- Two blocks mirroring the pure-core / boundary-shell split of lib/ma3.lua and
-- the shape of tests/test_store.lua:
--   1. PURE  — loads ma3.lua (+ its pure deps num/schema/breakdown) under the
--      BARE harness (no mock). Proves MA-free load (Pitfall 8) and exercises the
--      pure seams: setfader_args, index_from_pairs, resolve (GUID-only, NO addr
--      fallback), is_capturable (CAP-03 reuse of breakdown.is_excluded_master).
--   2. BOUNDARY — opt-in withAdapterMock (teardown-paired, RESEARCH Pitfall 1):
--      build_by_guid pool walk over a seeded tree, live-fader capture rounded via
--      num.round_fader (SP4 float), skip+notify on a GUID miss, and CAP-03
--      exclusion of speed/time masters.
-- No process-exit here (Pitfall 8 — run_all owns it).
local h = dofile((debug.getinfo(1,"S").source:sub(2):match("(.*/)") or "./") .. "helpers.lua")

local function keyCount(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

-- 1. PURE CORE — no mock installed; ma3.lua must load MA-free (Pitfall 8).
h.run("ma3 pure seams: setfader_args/index_from_pairs/resolve/is_capturable (OBJ-02/RCL-02/CAP-03)", function()
  h.loadModule("num.lua")
  h.loadModule("schema.lua")
  h.loadModule("breakdown.lua")
  local Ma3 = h.loadModule("ma3.lua")

  -- setfader_args: the EXACT SetFader table shape, no time field (RCL-02 apply contract)
  local args = Ma3.setfader_args(60)
  h.assertEq(args.value, 60, "setfader_args value==60")
  h.assertEq(args.token, "FaderMaster", "setfader_args token verbatim 'FaderMaster'")
  h.assertNil(args.time, "setfader_args carries NO time field (instant-set shape)")

  -- index_from_pairs: keep only string, non-empty guids; skip ""/nil (OBJ-02)
  local hA, hB, hX, hY = {}, {}, {}, {}
  local byGuid = Ma3.index_from_pairs({
    { guid = "A", handle = hA }, { guid = "",  handle = hX },
    { guid = nil, handle = hY }, { guid = "B", handle = hB },
  })
  h.assertEq(byGuid["A"], hA, "index keeps guid 'A'")
  h.assertEq(byGuid["B"], hB, "index keeps guid 'B'")
  h.assertNil(byGuid[""], "index skips empty-string guid")
  h.assertEq(keyCount(byGuid), 2, "index has exactly 2 keys (nil/empty dropped)")

  -- resolve: GUID-only; nil on miss AND on guid==nil (NO addr fallback) (OBJ-02)
  h.assertEq(Ma3.resolve({ guid = "A" }, byGuid), hA, "resolve GUID hit → handle")
  h.assertNil(Ma3.resolve({ guid = "Z" }, byGuid), "resolve GUID miss → nil")
  h.assertNil(Ma3.resolve({ addr = "1.201" }, byGuid), "resolve guid=nil → nil (NO addr fallback)")

  -- is_capturable: non-master types always true; masters reuse breakdown exclusion (CAP-03)
  h.assertTrue(Ma3.is_capturable({ type = "group" }), "group is capturable")
  h.assertTrue(Ma3.is_capturable({ type = "sequence" }), "sequence is capturable")
  h.assertTrue(Ma3.is_capturable({ type = "master", addr = "Master 2.1" }),
    "level master (Grand 2.1) is capturable")
  h.assertTrue(not Ma3.is_capturable({ type = "master", addr = "Master 3.1" }),
    "speed master (3.1) is NOT capturable (excluded)")

  -- refs_from_pairs: build typed schema refs; DROP any nil/""/"nil" guid so a bare
  -- exec slot (Pitfall 2 / T-08-01) can NEVER leak into an addr-keyed member (ASGN-04/06).
  local refs = Ma3.refs_from_pairs({
    { guid = "A", label = "Grp", addr = "Group 2" },
    { guid = "" },                                    -- empty  → dropped
    { guid = nil },                                   -- nil    → dropped
    { guid = "nil" },                                 -- "nil"  → dropped (bare-slot placeholder)
    { guid = "B", label = "Seq", addr = "Sequence 1" },
  }, "group")
  h.assertEq(#refs, 2, "refs_from_pairs kept exactly 2 (nil/''/'nil' guids dropped)")
  h.assertEq(refs[1].type, "group", "ref carries the passed kind (group)")
  h.assertEq(refs[1].label, "Grp", "ref[1] carries the pair's label")
  h.assertEq(refs[1].guid, "A", "ref[1] carries the pair's guid")
  h.assertEq(refs[1].addr, "Group 2", "ref[1] carries the pair's addr")
  h.assertEq(refs[2].guid, "B", "ref[2] is the second surviving guid B")
end)

-- 2. BOUNDARY SHELL — opt-in adapter mock; teardown-paired (leaves _G.Root nil).
h.run("ma3 boundary: build_by_guid/capture/skip-notify (OBJ-02/CAP-01..05)", function()
  local Ma3 = h.loadModule("ma3.lua")

  -- build_by_guid over a seeded tree resolves every seeded GUID; the nil-guid
  -- placeholder slot produces NO entry (Pitfall 4 — 13 slots for 1 real object).
  local seed = {
    groups    = { h.mockHandle{ guid = "G1", class = "Groups",    fader = 50 },
                  h.mockHandle{ guid = nil,  class = "Groups" } },   -- placeholder slot
    sequences = { h.mockHandle{ guid = "S1", class = "Sequences",  fader = 30 } },
    presets   = { h.mockHandle{ guid = "P1", class = "Pool",       fader = 10 } },
    masters   = { h.mockHandle{ guid = "M1", class = "Grand",      fader = 100 } },
  }
  h.withAdapterMock(seed, function(_ctl)
    local byGuid = Ma3.build_by_guid()
    h.assertTrue(Ma3.resolve({ guid = "G1" }, byGuid) ~= nil, "build_by_guid found group G1")
    h.assertTrue(Ma3.resolve({ guid = "S1" }, byGuid) ~= nil, "build_by_guid found sequence S1")
    h.assertTrue(Ma3.resolve({ guid = "P1" }, byGuid) ~= nil, "build_by_guid found preset P1 (nested pool)")
    h.assertTrue(Ma3.resolve({ guid = "M1" }, byGuid) ~= nil, "build_by_guid found level master M1")
    h.assertEq(keyCount(byGuid), 4, "build_by_guid map has exactly 4 keys (nil-guid slot dropped)")
  end)

  -- capture reads + rounds the live fader (SP4 float 59.999996 → 60) (CAP-02/05)
  h.withAdapterMock({ groups = { h.mockHandle{ guid = "G1", class = "Groups", fader = 59.999996 } } },
  function(_ctl)
    local out = Ma3.capture({ { guid = "G1", type = "group" } })
    h.assertEq(#out, 1, "capture returned one entry")
    h.assertEq(out[1].value, 60, "capture rounds 59.999996 → 60 (num.round_fader)")
    h.assertEq(out[1].ref.guid, "G1", "capture entry carries the source ref")
  end)

  -- capture a level master + a GUID-bearing exec-host both return their GetFader
  -- value (CAP-01 via hosted object / CAP-03 level master).
  h.withAdapterMock({
    masters   = { h.mockHandle{ guid = "M1", class = "Grand",     fader = 100 } },
    sequences = { h.mockHandle{ guid = "S1", class = "Sequences", fader = 42 } },   -- exec-host
  }, function(_ctl)
    local out = Ma3.capture({
      { guid = "M1", type = "master",   addr = "Master 2.1" },
      { guid = "S1", type = "executor" },                          -- GUID-bearing host (CAP-01)
    })
    h.assertEq(#out, 2, "capture returned both the level master and the exec-host")
    local byRef = {}
    for _, e in ipairs(out) do byRef[e.ref.guid] = e.value end
    h.assertEq(byRef["M1"], 100, "level master captured at 100")
    h.assertEq(byRef["S1"], 42, "GUID-bearing exec-host captured at 42 (CAP-01)")
  end)

  -- capture GUID miss → notify + continue (one unresolvable object never aborts).
  -- UI-03: the SAME skip-and-notify line must ALSO reach the System Monitor strip via
  -- Ma3.notify's guarded monitor.push (ADDED assertion; Printf assertions unchanged).
  local Mon = h.loadModule("monitor.lua"); Mon.clear()
  h.withAdapterMock({ groups = { h.mockHandle{ guid = "G1", class = "Groups", fader = 25 } } },
  function(ctl)
    local out = Ma3.capture({
      { guid = "G1",   type = "group" },
      { guid = "GONE", type = "group", label = "Missing" },        -- resolves to nil
    })
    h.assertEq(#out, 1, "capture skipped the missing GUID and kept G1")
    h.assertEq(out[1].ref.guid, "G1", "the one captured entry is G1")
    h.assertTrue(#ctl.msgs >= 1, "notify (skip+notify) fired for the GUID miss")
    local seenOnStrip = false
    for _, line in ipairs(Mon.list()) do
      if line:find("capture skip (GUID miss)", 1, true) then seenOnStrip = true end
    end
    h.assertTrue(seenOnStrip, "the skip line reached the monitor strip (Ma3.notify → monitor.push)")
  end)

  -- capture excludes speed/time masters via is_capturable (CAP-03).
  h.withAdapterMock({ masters = { h.mockHandle{ guid = "M1", class = "Grand", fader = 100 } } },
  function(_ctl)
    local out = Ma3.capture({
      { guid = "M1",  type = "master", addr = "Master 2.1" },      -- level → captured
      { guid = "SPD", type = "master", addr = "Master 3.1" },      -- speed → excluded
    })
    h.assertEq(#out, 1, "only the level master (2.1) was captured")
    h.assertEq(out[1].ref.guid, "M1", "the excluded speed master (3.1) was skipped")
  end)
end)

-- 2b. BOUNDARY SHELL — the NEW Phase-8 pool/address reads (ASGN-04/05/06). Same
-- teardown-paired withAdapterMock: pool_objects walks the seeded tree (nil-GUID slot
-- absent, presets nested, speed masters excluded), pool_counts aggregates, and
-- objects_from_addr resolves ObjectList(addr) skipping+notifying a bare exec slot.
h.run("ma3 boundary: pool_objects/pool_counts/objects_from_addr (ASGN-04/05/06)", function()
  local Ma3 = h.loadModule("ma3.lua")

  -- pool_objects("group"): every GUID-bearing group; the nil-GUID placeholder slot
  -- (Pitfall 4 — 13 slots for 1 real object) is dropped by the pure seam.
  h.withAdapterMock({
    groups = { h.mockHandle{ guid = "G1", name = "Blinders" },
               h.mockHandle{ guid = nil,  name = "empty slot" } },     -- placeholder → dropped
  }, function(_ctl)
    local refs = Ma3.pool_objects("group")
    h.assertEq(#refs, 1, "pool_objects('group') listed exactly the 1 GUID-bearing group")
    h.assertEq(refs[1].guid, "G1", "the listed group is G1")
    h.assertEq(refs[1].type, "group", "the ref is typed 'group'")
    h.assertEq(refs[1].label, "Blinders", "the ref label is the Get('Name') value")
  end)

  -- pool_objects("sequence"): the Sequences pool, typed "sequence".
  h.withAdapterMock({
    sequences = { h.mockHandle{ guid = "S1", name = "Main Cue" } },
  }, function(_ctl)
    local refs = Ma3.pool_objects("sequence")
    h.assertEq(#refs, 1, "pool_objects('sequence') lists the sequence pool")
    h.assertEq(refs[1].guid, "S1", "sequence S1 listed")
    h.assertEq(refs[1].type, "sequence", "typed 'sequence'")
  end)

  -- pool_objects("preset"): the nested preset-pool children, typed "preset".
  h.withAdapterMock({
    presets = { h.mockHandle{ guid = "P1", name = "Color 1" } },       -- nested under a preset pool
  }, function(_ctl)
    local refs = Ma3.pool_objects("preset")
    h.assertEq(#refs, 1, "pool_objects('preset') lists the nested preset pool")
    h.assertEq(refs[1].guid, "P1", "preset P1 listed")
    h.assertEq(refs[1].type, "preset", "typed 'preset'")
  end)

  -- pool_objects("executor"): the objects ON executor faders via each executor's
  -- GetAssignedObj() (mixed classes). A bare slot (assigned=nil) is skipped. Typed "executor".
  h.withAdapterMock({
    execs = {
      h.mockHandle{ assigned = h.mockHandle{ guid = "S1", name = "ProbeSeq",    class = "Sequence" } },
      h.mockHandle{ assigned = h.mockHandle{ guid = "G1", name = "ProbeGrp",    class = "Group" } },
      h.mockHandle{ assigned = h.mockHandle{ guid = "P1", name = "ProbePreset", class = "Preset" } },
      h.mockHandle{ assigned = nil },                                              -- bare slot → skipped
    },
  }, function(_ctl)
    local refs = Ma3.pool_objects("executor")
    h.assertEq(#refs, 3, "pool_objects('executor') = only faders WITH an assigned object")
    local byGuid = {}
    for _, r in ipairs(refs) do byGuid[r.guid] = r end
    -- each fader object keeps its REAL type (mixed) — the executor is just a locator
    h.assertEq(byGuid["S1"].type, "sequence", "sequence on a fader keeps type 'sequence'")
    h.assertEq(byGuid["G1"].type, "group",    "group on a fader keeps type 'group'")
    h.assertEq(byGuid["P1"].type, "preset",   "preset on a fader keeps type 'preset'")
  end)

  -- class_to_type maps MA3 class names (variants/substrings) to ref types.
  h.assertEq(Ma3.class_to_type("Sequence"), "sequence", "Sequence → sequence")
  h.assertEq(Ma3.class_to_type("CuePool"),  "sequence", "cue-ish → sequence")
  h.assertEq(Ma3.class_to_type("Group"),    "group",    "Group → group")
  h.assertEq(Ma3.class_to_type("PresetPool"),"preset",  "Preset → preset")
  h.assertEq(Ma3.class_to_type("Macro"),    "executor", "unknown → executor fallback")

  -- pool_objects("master"): lists level masters, EXCLUDES a speed master via
  -- is_excluded_master (the Name is the "Master C.N" addr the filter parses).
  h.withAdapterMock({
    masters = { h.mockHandle{ guid = "M1",  name = "Master 2.1" },      -- level → listed
                h.mockHandle{ guid = "SPD", name = "Master 3.1" } },    -- speed → excluded
  }, function(_ctl)
    local refs = Ma3.pool_objects("master")
    h.assertEq(#refs, 1, "pool_objects('master') listed only the level master")
    h.assertEq(refs[1].guid, "M1", "the excluded speed master (3.1) is absent")
    h.assertEq(refs[1].type, "master", "the ref is typed 'master'")
  end)

  -- pool_counts(): {executor,sequence,preset,group,master} matching the seeded counts.
  h.withAdapterMock({
    groups    = { h.mockHandle{ guid = "G1", name = "Grp" } },
    sequences = { h.mockHandle{ guid = "S1", name = "Seq" } },
    presets   = { h.mockHandle{ guid = "P1", name = "Pre" } },
    execs     = { h.mockHandle{ assigned = h.mockHandle{ guid = "S1", name = "Seq" } } },  -- 1 on a fader
    masters   = { h.mockHandle{ guid = "M1", name = "Master 2.1" },     -- level → counted
                  h.mockHandle{ guid = "SPD", name = "Master 3.1" } },  -- speed → excluded
  }, function(_ctl)
    local c = Ma3.pool_counts()
    h.assertEq(c.group,    1, "pool_counts.group == 1")
    h.assertEq(c.sequence, 1, "pool_counts.sequence == 1")
    h.assertEq(c.preset,   1, "pool_counts.preset == 1")
    h.assertEq(c.executor, 1, "pool_counts.executor == 1 (one fader assignment)")
    h.assertEq(c.master,   1, "pool_counts.master == 1 (speed master excluded)")
  end)

  -- objects_from_addr("Group 2","group"): ObjectList resolves 1 GUID-bearing group.
  h.withAdapterMock({
    objectlist = { ["Group 2"] = { h.mockHandle{ guid = "G2", name = "Blinders" } } },
  }, function(_ctl)
    local refs = Ma3.objects_from_addr("Group 2", "group")
    h.assertEq(#refs, 1, "objects_from_addr('Group 2') resolved 1 group ref (ASGN-06)")
    h.assertEq(refs[1].guid, "G2", "the resolved group ref is G2")
    h.assertEq(refs[1].addr, "Group 2", "the ref carries the command-line address")
  end)

  -- objects_from_addr("Executor 201",…): the bare exec slot has GUID nil (Pitfall 2)
  -- → 0 refs AND a skip+notify fires (the operator sees why the slot was not added).
  h.withAdapterMock({
    objectlist = { ["Executor 201"] = { h.mockHandle{ guid = nil, name = "slot" } } },
  }, function(ctl)
    local refs = Ma3.objects_from_addr("Executor 201", "executor")
    h.assertEq(#refs, 0, "objects_from_addr drops the nil-GUID bare exec slot (GUID-only)")
    h.assertTrue(#ctl.msgs >= 1, "skip+notify fired for the bare exec slot (no GUID)")
  end)
end)

-- after the withAdapterMock blocks exit, the console globals must be nil again so
-- test_boundary.lua (which asserts _G.Root == nil) stays green (Pitfall 6 teardown).
h.run("ma3 boundary teardown: Root/ObjectList restored to nil (Pitfall 6)", function()
  h.assertNil(_G.Root, "_G.Root torn down to nil after withAdapterMock")
  h.assertNil(_G.ObjectList, "_G.ObjectList torn down to nil after withAdapterMock")
end)

-- 3. FADE-APPLY (RCL-02) — the uniform Lua value-animation engine. Instant-set
-- exact land (fade<=0 / nil), stepped tween interpolation via the synchronous
-- mock Timer, the generation guard cancelling a superseded recall (manual_timer),
-- and skip+notify on a GUID miss during recall (emit-always / continue). recall
-- reuses the pure Snapshots.fade.interp for the per-frame value math.
h.run("ma3 recall: instant-set / tween / generation-guard / skip-notify (RCL-02)", function()
  h.loadModule("num.lua")
  h.loadModule("schema.lua")
  h.loadModule("breakdown.lua")
  h.loadModule("fade.lua")          -- recall reuses Snapshots.fade.interp for value math
  local Ma3 = h.loadModule("ma3.lua")

  -- instant-set (fade_time = 0): every target lands the EXACT stored `to`.
  h.withAdapterMock({ groups = { h.mockHandle{ guid = "G1", class = "Groups", fader = 0 } } },
  function(ctl)
    local plan = { { ref = { guid = "G1", type = "group" }, value = 80 } }
    local byGuid = Ma3.build_by_guid()
    Ma3.recall(plan, 0)
    local h1 = Ma3.resolve({ guid = "G1" }, byGuid)
    h.assertEq(h1:GetFader(), 80, "instant-set fade=0 → live fader lands exact 80")
    h.assertTrue(#ctl.writes >= 1, "instant-set wrote at least once")
    h.assertEq(ctl.writes[#ctl.writes].value, 80, "instant-set last write == to (80)")
    h.assertEq(ctl.writes[#ctl.writes].guid, "G1", "instant-set wrote G1")
  end)

  -- instant-set (fade_time = nil): nil fade also lands exact (no Timer path).
  h.withAdapterMock({ groups = { h.mockHandle{ guid = "G1", class = "Groups", fader = 10 } } },
  function(ctl)
    local plan = { { ref = { guid = "G1", type = "group" }, value = 55 } }
    local byGuid = Ma3.build_by_guid()
    Ma3.recall(plan, nil)
    local h1 = Ma3.resolve({ guid = "G1" }, byGuid)
    h.assertEq(h1:GetFader(), 55, "instant-set fade=nil → live fader lands exact 55")
    h.assertEq(ctl.writes[#ctl.writes].value, 55, "nil-fade last write == to (55)")
  end)

  -- tween interpolation (auto Timer, fade_time = 0.1): stepped writes, an
  -- intermediate strictly between from(0) and to(80), and a final exact 80.
  h.withAdapterMock({ groups = { h.mockHandle{ guid = "G1", class = "Groups", fader = 0 } },
                      time_start = 1000.0, time_step = 0.02 },
  function(ctl)
    local plan = { { ref = { guid = "G1", type = "group" }, value = 80 } }
    Ma3.recall(plan, 0.1)
    h.assertTrue(#ctl.writes > 1, "tween produced MULTIPLE writes (stepped, not a snap)")
    local sawIntermediate = false
    for _, w in ipairs(ctl.writes) do
      if w.value > 0 and w.value < 80 then sawIntermediate = true end
    end
    h.assertTrue(sawIntermediate, "tween wrote an intermediate strictly between from(0) and to(80)")
    h.assertEq(ctl.writes[#ctl.writes].value, 80, "tween FINAL write == to (80) via done()/apply_final")
  end)

  -- generation guard (manual_timer): a stale tick + cleanup AFTER bumping
  -- Ma3._gen writes nothing — the superseded recall was cancelled (Pitfall 3).
  h.withAdapterMock({ groups = { h.mockHandle{ guid = "G1", class = "Groups", fader = 0 } },
                      time_start = 1000.0, time_step = 0.02, manual_timer = true },
  function(ctl)
    local plan = { { ref = { guid = "G1", type = "group" }, value = 80 } }
    Ma3.recall(plan, 0.1)
    h.assertTrue(#ctl.timers >= 1, "manual_timer recorded the tween job without auto-running")
    local job = ctl.timers[1]
    local baseline = #ctl.writes
    Ma3._gen = Ma3._gen + 1            -- simulate a superseding recall bumping the counter
    job.fn()                            -- a stale tick — must no-op under the guard
    if job.cleanup then job.cleanup() end  -- a stale done — must no-op under the guard
    h.assertEq(#ctl.writes, baseline, "superseded recall's stale tick/done wrote NOTHING (generation guard)")
  end)

  -- WR-01: an INSTANT recall must supersede a still-pending tween. Start tween A
  -- (records a manual job, no auto-run), fire instant recall B to a different value;
  -- B bumps Ma3._gen at the TOP of recall, so A's later tick/done write NOTHING and
  -- cannot drag the fader back off B's value ("recall reliably, every show").
  h.withAdapterMock({ groups = { h.mockHandle{ guid = "G1", class = "Groups", fader = 0 } },
                      time_start = 1000.0, time_step = 0.02, manual_timer = true },
  function(ctl)
    Ma3.recall({ { ref = { guid = "G1", type = "group" }, value = 80 } }, 3)  -- tween A (pending)
    local jobA = ctl.timers[#ctl.timers]
    Ma3.recall({ { ref = { guid = "G1", type = "group" }, value = 20 } }, 0)  -- instant B supersedes
    local handle = Ma3.resolve({ guid = "G1" }, Ma3.build_by_guid())
    h.assertEq(handle:GetFader(), 20, "instant recall B landed exact 20")
    local afterB = #ctl.writes
    jobA.fn()                                -- A's stale tick — must no-op
    if jobA.cleanup then jobA.cleanup() end  -- A's stale done — must no-op
    h.assertEq(#ctl.writes, afterB, "superseded tween A wrote NOTHING after instant recall B (WR-01)")
    h.assertEq(handle:GetFader(), 20, "fader stays at B's value; A did not drag it back")
  end)

  -- recall skip+notify: a GUID miss is notified and the recall CONTINUES for the
  -- resolvable targets (emit-always / continue) — G1 still lands, GONE is skipped.
  h.withAdapterMock({ groups = { h.mockHandle{ guid = "G1", class = "Groups", fader = 0 } } },
  function(ctl)
    local plan = {
      { ref = { guid = "G1",   type = "group" }, value = 80 },
      { ref = { guid = "GONE", type = "group", label = "Missing" }, value = 50 },
    }
    local byGuid = Ma3.build_by_guid()
    Ma3.recall(plan, 0)
    local h1 = Ma3.resolve({ guid = "G1" }, byGuid)
    h.assertEq(h1:GetFader(), 80, "recall drove the resolvable target G1 to 80")
    h.assertTrue(#ctl.msgs >= 1, "skip+notify fired for the GUID miss (GONE)")
  end)

  -- uniform across types: a group + a level master both driven to their stored
  -- values by the SAME engine (object-independent — RCL-02 uniform apply).
  h.withAdapterMock({
    groups  = { h.mockHandle{ guid = "G1", class = "Groups", fader = 0 } },
    masters = { h.mockHandle{ guid = "M1", class = "Grand",  fader = 0 } },
  }, function(ctl)
    local plan = {
      { ref = { guid = "G1", type = "group" },  value = 80 },
      { ref = { guid = "M1", type = "master", addr = "Master 2.1" }, value = 100 },
    }
    local byGuid = Ma3.build_by_guid()
    Ma3.recall(plan, 0)
    h.assertEq(Ma3.resolve({ guid = "G1" }, byGuid):GetFader(), 80, "group G1 driven to 80 (uniform)")
    h.assertEq(Ma3.resolve({ guid = "M1" }, byGuid):GetFader(), 100, "level master M1 driven to 100 (uniform)")
  end)
end)
