-- tests/test_model.lua — snapshot data model (CAP-04 / RCL-01 / D-09 / D-10).
-- Covers new_snapshot (fade default), set_member (append + in-place dedup by
-- schema.key), parked-kept (assigned=false stays in snap.members — D-10), and
-- recall_plan (assigned-only {ref,value} — RCL-01). Loads schema.lua too so the
-- call-time Snapshots.schema.key lookup resolves (SHARED-B).
-- No process-exit call here (Pitfall 8 — run_all owns it).
local h = dofile((debug.getinfo(1,"S").source:sub(2):match("(.*/)") or "./") .. "helpers.lua")
h.run("model new_snapshot/set_member/recall_plan (CAP-04, RCL-01, D-10)", function()
  local Schema = h.loadModule("schema.lua")   -- sibling for call-time key()
  local Model  = h.loadModule("model.lua")

  -- new_snapshot: name/fade/members shape; fade defaults to 0
  local snap = Model.new_snapshot("Verse", 3)
  h.assertEq(snap.name, "Verse", "snapshot name set")
  h.assertEq(snap.fade, 3, "snapshot default fade set")
  h.assertEq(#snap.members, 0, "new snapshot has no members")
  local nofade = Model.new_snapshot("X")
  h.assertEq(nofade.fade, 0, "fade defaults to 0 when omitted")

  -- set_member: append an assigned member
  local grp  = Schema.new_ref{ type="group", addr="Group 2", guid="8A 60" }
  local exec = Schema.new_ref{ type="executor", addr="1.201" }   -- guid nil → @addr key
  local ma   = Model.set_member(snap, grp, true, 75)
  h.assertEq(#snap.members, 1, "first set_member appends")
  h.assertEq(ma.assigned, true, "member assigned true")
  h.assertEq(ma.value, 75, "CAP-04: stored value 75")

  -- dedup by schema.key: same-key ref UPDATES in place (no duplicate)
  local grp2 = Schema.new_ref{ type="group", addr="Group 2", guid="8A 60" }
  Model.set_member(snap, grp2, true, 40)
  h.assertEq(#snap.members, 1, "same-key set_member updates in place (no dup)")
  h.assertEq(snap.members[1].value, 40, "in-place update overwrites value")

  -- executor ref (addr-keyed) never collides with guid'd group → new member
  Model.set_member(snap, exec, true, 100)
  h.assertEq(#snap.members, 2, "disjoint key (executor @addr) appends new member")

  -- parked member: assigned=false is KEPT in snap.members (D-10)
  local prk = Schema.new_ref{ type="master", addr="Master 2.1", guid="AA 01" }
  Model.set_member(snap, prk, false, 50)
  h.assertEq(#snap.members, 3, "parked member kept in members")
  h.assertEq(snap.members[3].assigned, false, "parked member assigned=false")

  -- recall_plan: assigned-only {ref,value}; parked absent from plan (RCL-01)
  local plan = Model.recall_plan(snap)
  h.assertEq(#plan, 2, "recall_plan returns only assigned members (parked excluded)")
  for _, p in ipairs(plan) do
    h.assertTrue(p.ref ~= nil, "plan entry carries ref")
    h.assertTrue(type(p.value) == "number", "plan entry carries numeric value")
    h.assertTrue(Schema.key(p.ref) ~= Schema.key(prk), "parked ref never in plan")
  end

  -- parked member still present in snap.members after recall_plan (D-10)
  local still_parked = false
  for _, m in ipairs(snap.members) do
    if Schema.key(m.ref) == Schema.key(prk) then still_parked = true end
  end
  h.assertTrue(still_parked, "parked member STILL in snap.members after recall_plan")

  -- re-ticking a parked member flips it back to assigned (UI re-tick path)
  Model.set_member(snap, prk, true, 60)
  h.assertEq(#snap.members, 3, "re-tick updates in place (no new member)")
  h.assertEq(#Model.recall_plan(snap), 3, "re-ticked member now appears in plan")
end)
