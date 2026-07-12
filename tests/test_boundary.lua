-- tests/test_boundary.lua — boundary smoke test (D-06 part 1).
-- Asserts the harness leaves the four MA3 globals UNDEFINED so any pure-logic
-- reach for them crashes loudly. No process-exit call here (Pitfall 8) —
-- run_all.lua owns the single exit.
local h = dofile((debug.getinfo(1,"S").source:sub(2):match("(.*/)") or "./") .. "helpers.lua")
h.run("MA3 globals left undefined by harness", function()
  h.assertNil(_G.Cmd,        "Cmd must be undefined")
  h.assertNil(_G.Obj,        "Obj must be undefined")
  h.assertNil(_G.Root,       "Root must be undefined")
  h.assertNil(_G.GlobalVars, "GlobalVars must be undefined")
end)
