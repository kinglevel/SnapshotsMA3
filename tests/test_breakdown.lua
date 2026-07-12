-- tests/test_breakdown.lua — Snapshots.breakdown coverage (RCL-05, D-11..D-13).
-- Header copied from test_boundary.lua:5 (Pitfall 8 — run_all.lua owns os.exit).
local h = dofile((debug.getinfo(1,"S").source:sub(2):match("(.*/)") or "./") .. "helpers.lua")
local B = h.loadModule("breakdown.lua")

-- Task 1: is_excluded_master — data-driven exclusion predicate (D-12).
h.run("is_excluded_master: level masters (incl. Grand 2.1) are NOT excluded", function()
  h.assertEq(B.is_excluded_master({ type = "master", addr = "Master 2.1"  }), false, "Grand 2.1 included")
  h.assertEq(B.is_excluded_master({ type = "master", addr = "Master 2.2"  }), false, "World 2.2 included")
  h.assertEq(B.is_excluded_master({ type = "master", addr = "Master 2.5"  }), false, "Solo 2.5 included")
  h.assertEq(B.is_excluded_master({ type = "master", addr = "Master 2.12" }), false, "Blind 2.12 included")
  h.assertEq(B.is_excluded_master({ type = "master", addr = "Master 2.14" }), false, "SoundIn 2.14 included")
end)

h.run("is_excluded_master: cat-2 timing entries ARE excluded", function()
  h.assertEq(B.is_excluded_master({ type = "master", addr = "Master 2.6"  }), true, "Rate 2.6 excluded")
  h.assertEq(B.is_excluded_master({ type = "master", addr = "Master 2.8"  }), true, "ProgramTime 2.8 excluded")
  h.assertEq(B.is_excluded_master({ type = "master", addr = "Master 2.15" }), true, "SoundFade 2.15 excluded")
end)

h.run("is_excluded_master: whole cats 3/4/5 are excluded wholesale", function()
  h.assertEq(B.is_excluded_master({ type = "master", addr = "Master 3.4"  }), true, "cat 3 Speed excluded")
  h.assertEq(B.is_excluded_master({ type = "master", addr = "Master 4.10" }), true, "cat 4 Playback excluded")
  h.assertEq(B.is_excluded_master({ type = "master", addr = "Master 5.7"  }), true, "cat 5 Timing excluded")
end)

h.run("is_excluded_master: non-master / unparseable addr → not excluded", function()
  h.assertEq(B.is_excluded_master({ type = "group",    addr = "Group 2" }), false, "Group addr not a master")
  h.assertEq(B.is_excluded_master({ type = "executor", addr = "1.201"   }), false, "Executor addr not a master")
  h.assertEq(B.is_excluded_master({ addr = "garbage"                    }), false, "unparseable addr")
end)

-- Task 2: select_targets — category-based override to 100 (D-11, D-13).
h.run("select_targets: eligible objects → to=100, excluded masters absent", function()
  local ref_exec  = { type = "executor", addr = "1.201"      }
  local ref_seq   = { type = "sequence", addr = "Sequence 3" }
  local ref_prst  = { type = "preset",   addr = "Preset 4.7" }
  local ref_group = { type = "group",    addr = "Group 2"    }
  local ref_grand = { type = "master",   addr = "Master 2.1"  }  -- level master → included
  local ref_blind = { type = "master",   addr = "Master 2.12" }  -- level master → included
  local ref_rate  = { type = "master",   addr = "Master 2.6"  }  -- Rate → excluded
  local ref_sfade = { type = "master",   addr = "Master 2.15" }  -- SoundFade → excluded
  local ref_timg  = { type = "master",   addr = "Master 5.7"  }  -- cat-5 Timing → excluded

  local plan = {
    { ref = ref_exec,  value = 50 },
    { ref = ref_seq,   value = 0  },
    { ref = ref_prst,  value = 75 },
    { ref = ref_group, value = 33 },
    { ref = ref_grand, value = 10 },
    { ref = ref_blind, value = 90 },
    { ref = ref_rate,  value = 42 },
    { ref = ref_sfade, value = 42 },
    { ref = ref_timg,  value = 42 },
  }

  local out = B.select_targets(plan)

  -- (c) eligible count = 6 (exec, seq, preset, group, Grand, Blind)
  h.assertEq(#out, 6, "eligible count")

  -- (a) every included entry overrides stored value to 100 (D-11)
  local seen = {}
  for _, e in ipairs(out) do
    h.assertEq(e.to, 100, "to=100 for "..tostring(e.ref.addr))
    seen[e.ref] = true
  end

  -- (d) category-based: executor, sequence, preset, group, Grand, Blind present (D-13)
  h.assertTrue(seen[ref_exec],  "executor present")
  h.assertTrue(seen[ref_seq],   "sequence present (D-13, not type-gated)")
  h.assertTrue(seen[ref_prst],  "preset present (D-13, not type-gated)")
  h.assertTrue(seen[ref_group], "group present")
  h.assertTrue(seen[ref_grand], "Grand 2.1 present")
  h.assertTrue(seen[ref_blind], "Blind 2.12 present")

  -- (b) the three timing/speed masters are absent
  h.assertEq(seen[ref_rate]  or false, false, "Rate 2.6 excluded")
  h.assertEq(seen[ref_sfade] or false, false, "SoundFade 2.15 excluded")
  h.assertEq(seen[ref_timg]  or false, false, "Timing 5.7 excluded")
end)
