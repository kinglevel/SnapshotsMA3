-- tests/test_schema.lua — object-ref schema (OBJ-01 / D-08) + CAP-04 value round-trip.
-- Covers new_ref construct/validate, key (guid-first, "@"..addr for executors),
-- and a vendored-json round-trip incl. the executor guid==nil case (Pitfall 5:
-- json drops a nil key on encode, so it decodes absent, not a sentinel).
-- No process-exit call here (Pitfall 8 — run_all owns it).
local h = dofile((debug.getinfo(1,"S").source:sub(2):match("(.*/)") or "./") .. "helpers.lua")
h.run("schema.new_ref / key + json round-trip (OBJ-01, CAP-04)", function()
  local Schema = h.loadModule("schema.lua")
  local json   = require("json")

  -- construct: all 5 fields set
  local grp = Schema.new_ref{ type="group", addr="Group 2", guid="8A 60",
                              label="ProbeGrp", datapool=1 }
  h.assertEq(grp.type,     "group",    "type set")
  h.assertEq(grp.addr,     "Group 2",  "addr set")
  h.assertEq(grp.guid,     "8A 60",    "guid set")
  h.assertEq(grp.label,    "ProbeGrp", "label set")
  h.assertEq(grp.datapool, 1,          "datapool set")

  -- validate: bad type raises
  h.assertTrue(not (pcall(Schema.new_ref, { type="fixture", addr="x" })),
    "type not in TYPES raises")
  -- validate: neither guid nor addr raises
  h.assertTrue(not (pcall(Schema.new_ref, { type="group" })),
    "missing guid AND addr raises")

  -- executor: guid nil is allowed
  local exec = Schema.new_ref{ type="executor", addr="1.201" }
  h.assertNil(exec.guid, "executor ref has nil guid")
  h.assertEq(exec.addr, "1.201", "executor addr set")

  -- key: guid-first, "@"..addr fallback for executors
  h.assertEq(Schema.key(grp),  "8A 60",   "key uses guid when present")
  h.assertEq(Schema.key(exec), "@1.201",  "key uses @addr when guid nil")

  -- json round-trip: guid ref restores field-by-field
  local dg = json.decode(json.encode(grp))
  h.assertEq(dg.guid,     "8A 60",    "guid round-trips")
  h.assertEq(dg.addr,     "Group 2",  "addr round-trips")
  h.assertEq(dg.label,    "ProbeGrp", "label round-trips")
  h.assertEq(dg.type,     "group",    "type round-trips")
  h.assertEq(dg.datapool, 1,          "datapool round-trips")

  -- json round-trip: executor guid==nil decodes absent (Pitfall 5)
  local encExec = json.encode(exec)
  h.assertTrue(type(encExec) == "string", "encode returns a string")
  local de = json.decode(encExec)
  h.assertNil(de.guid, "executor decoded guid == nil (nil key dropped on encode)")
  h.assertEq(de.addr, "1.201", "executor addr preserved through round-trip")

  -- CAP-04: a numeric value carried alongside the ref survives round-trip
  local slot = { ref = grp, assigned = true, value = 59 }
  local ds = json.decode(json.encode(slot))
  h.assertEq(ds.value, 59, "CAP-04 numeric value 0..100 round-trips")
  h.assertTrue(ds.assigned == true, "assigned bool round-trips")
end)
