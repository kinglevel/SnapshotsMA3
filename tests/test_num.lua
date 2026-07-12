-- tests/test_num.lua — float-epsilon helpers (SP4 fader imprecision).
-- Proves approx_eq tolerates SetFader(60)->59.999996, round_fader snaps it,
-- and clamp bounds a value. No process-exit call here (Pitfall 8 — run_all owns it).
local h = dofile((debug.getinfo(1,"S").source:sub(2):match("(.*/)") or "./") .. "helpers.lua")
h.run("num.approx_eq / clamp / round_fader behave", function()
  local Num = h.loadModule("num.lua")

  -- approx_eq: SP4 imprecision tolerated at default eps 1e-3
  h.assertTrue(Num.approx_eq(59.999996, 60),  "59.999996 ~= 60 within default eps")
  h.assertTrue(not Num.approx_eq(59.9, 60),   "59.9 is NOT within default eps of 60")
  -- caller-supplied eps honored
  h.assertTrue(Num.approx_eq(59.9, 60, 0.2),  "59.9 ~= 60 within caller eps 0.2")
  h.assertTrue(not Num.approx_eq(59.9, 60, 0.05), "59.9 NOT within caller eps 0.05")

  -- round_fader: snaps float-imprecise fader reads to the integer
  h.assertEq(Num.round_fader(59.999996), 60, "round_fader 59.999996 -> 60")
  h.assertEq(Num.round_fader(41.999996), 42, "round_fader 41.999996 -> 42")
  h.assertEq(Num.round_fader(25.0),      25, "round_fader 25.0 -> 25")

  -- clamp: bounds into [lo,hi]
  h.assertEq(Num.clamp(150, 0, 100), 100, "clamp 150 -> 100")
  h.assertEq(Num.clamp(-5, 0, 100),  0,   "clamp -5 -> 0")
  h.assertEq(Num.clamp(50, 0, 100),  50,  "clamp 50 -> 50 (in range)")

  -- module attaches under the namespace
  h.assertTrue(_G.Snapshots.num == Num, "Snapshots.num == returned table")
end)
