-- tests/test_fade.lua — pure tween math (D-01 / D-02 / D-03).
-- Covers interp (formula from+(to-from)*(u/100), EXACT endpoints via assertEq,
-- midpoints via assertNear, clamped out-of-range u), resolve_time truth table
-- (RCL-03 arg overrides default; non-number arg ignored; nil→0), and build_targets
-- ({ref,to} only — NO from, which is live Phase-5 GetFader state). Loads num.lua
-- as the sibling (SHARED-B) even though interp's exact endpoints avoid drift.
-- No process-exit call here (Pitfall 8 — run_all owns it).
local h = dofile((debug.getinfo(1,"S").source:sub(2):match("(.*/)") or "./") .. "helpers.lua")
h.run("fade interp/resolve_time/build_targets (D-01..D-03, RCL-03)", function()
  local Num  = h.loadModule("num.lua")    -- sibling for any call-time rounding
  local Fade = h.loadModule("fade.lua")

  -- interp: EXACT endpoints (assertEq — no float drift at the ends)
  h.assertEq(Fade.interp(0, 100, 0),   0,   "interp endpoint u=0 → from (exact)")
  h.assertEq(Fade.interp(0, 100, 100), 100, "interp endpoint u=100 → to (exact)")
  h.assertEq(Fade.interp(20, 60, 0),   20,  "interp endpoint u=0 → 20 (exact)")
  h.assertEq(Fade.interp(20, 60, 100), 60,  "interp endpoint u=100 → 60 (exact)")

  -- interp: clamp out-of-range u to the exact endpoints
  h.assertEq(Fade.interp(0, 100, -10), 0,   "interp clamps u<0 → from")
  h.assertEq(Fade.interp(0, 100, 150), 100, "interp clamps u>100 → to")

  -- interp: midpoints (assertNear — the interpolation math)
  h.assertNear(Fade.interp(0, 100, 50), 50, 1e-3, "interp(0,100,50) ≈ 50")
  h.assertNear(Fade.interp(20, 60, 25), 30, 1e-3, "interp(20,60,25) ≈ 30")
  h.assertNear(Fade.interp(0, 100, 75), 75, 1e-3, "interp(0,100,75) ≈ 75")

  -- resolve_time truth table (RCL-03): arg-wins / default / nil→0 / non-number→default
  h.assertEq(Fade.resolve_time(3, 5),     5, "arg (number) overrides default")
  h.assertEq(Fade.resolve_time(3, nil),   3, "nil arg → snapshot default")
  h.assertEq(Fade.resolve_time(nil, nil), 0, "both nil → 0")
  h.assertEq(Fade.resolve_time(3, "abc"), 3, "non-number arg ignored → default")
  h.assertEq(Fade.resolve_time(3, 0),     0, "arg 0 is a valid number (overrides)")

  -- build_targets: {ref,to} only — emits to=value, NO from key present
  local r1, r2 = { addr = "Group 2" }, { addr = "1.201" }
  local plan   = { { ref = r1, value = 75 }, { ref = r2, value = 40 } }
  local out    = Fade.build_targets(plan)
  h.assertEq(#out, 2, "build_targets maps every plan entry")
  h.assertTrue(out[1].ref == r1, "build_targets carries ref through")
  h.assertEq(out[1].to, 75, "build_targets emits to=value (entry 1)")
  h.assertEq(out[2].to, 40, "build_targets emits to=value (entry 2)")
  h.assertNil(out[1].from, "build_targets emits NO from (live Phase-5 GetFader)")
  h.assertNil(out[2].from, "build_targets emits NO from (entry 2)")
end)
