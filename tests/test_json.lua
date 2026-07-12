-- tests/test_json.lua — vendored json.lua round-trip (D-06 part 2).
-- Proves the off-desk JSON path Phase 4's persistence boundary depends on.
-- No process-exit call here (Pitfall 8).
local h = dofile((debug.getinfo(1,"S").source:sub(2):match("(.*/)") or "./") .. "helpers.lua")
h.run("vendored json.lua encode/decode round-trips", function()
  local json = require("json")                 -- resolved via package.path aug in helpers.lua
  local orig = { name = "Verse", fade = 3, objs = { "a", "b" }, on = true }
  local encoded = json.encode(orig)
  h.assertTrue(type(encoded) == "string", "encode returns a string")
  local dec = json.decode(encoded)
  h.assertEq(dec.name, "Verse")
  h.assertEq(dec.fade, 3)
  h.assertEq(dec.objs[2], "b")
  h.assertTrue(dec.on == true, "bool round-trips")
end)
