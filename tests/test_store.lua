-- tests/test_store.lua — persistence boundary (PER-01..04 / D-06 / §4).
-- Two blocks mirroring the pure-core / boundary-shell split of lib/store.lua:
--   1. PURE  — loads store.lua under the BARE harness (no mock). empty_state,
--      encode/decode round-trip, per-id merge overlay/delete, corrupt-report
--      (decode returns the raw bytes as 2nd value), string-key discipline.
--   2. BOUNDARY — opt-in withGlobalVarsMock (teardown-paired, RESEARCH Pitfall 1):
--      lazy-init (load never writes), round-trip (value is always a JSON string),
--      re-read delta (no-clobber of a peer id), targeted delete, corrupt→empty +
--      Snapshots_bak raw-byte backup, and clear (delete-all).
-- No process-exit here (Pitfall 8 — run_all owns it).
local h = dofile((debug.getinfo(1,"S").source:sub(2):match("(.*/)") or "./") .. "helpers.lua")

-- 1. PURE CORE — no mock installed; store.lua must load MA-free (Pitfall 6).
h.run("store pure core: empty/encode/decode/merge/corrupt-report (PER-01/PER-04)", function()
  local S = h.loadModule("store.lua")

  -- empty_state: lazy shape, starts empty (PER-04)
  local st = S.empty_state()
  h.assertEq(st.version, 1, "empty_state version==1")
  h.assertNil(next(st.snapshots), "empty_state snapshots is empty")

  -- encode → string; decode round-trips the collection (PER-01)
  local merged = S.merge_save(S.empty_state(), "id-A", { name = "Verse", fade = 3, members = {} })
  local enc = S.encode(merged)
  h.assertEq(type(enc), "string", "encode returns a JSON string")
  local back = S.decode(enc)
  h.assertEq(back.snapshots["id-A"].name, "Verse", "decode(encode(..)) round-trips id-A name")

  -- merge_save overlays ONLY the given id; merge_delete removes only its id
  local base = S.empty_state()
  base.snapshots["peer-B"] = { name = "Chorus", fade = 0, members = {} }
  S.merge_save(base, "mine-A", { name = "Solo", fade = 1, members = {} })
  h.assertTrue(base.snapshots["peer-B"] ~= nil, "merge_save preserves the pre-existing peer id")
  h.assertTrue(base.snapshots["mine-A"] ~= nil, "merge_save adds the new id")
  S.merge_delete(base, "peer-B")
  h.assertNil(base.snapshots["peer-B"], "merge_delete removes only its id")
  h.assertTrue(base.snapshots["mine-A"] ~= nil, "merge_delete leaves the other id")

  -- corrupt input: decode REPORTS (empty_state, corrupt_raw) and never errors (PER-04)
  local st2, corrupt = S.decode("{not json")
  h.assertTrue(corrupt ~= nil, "decode reports corrupt bytes as 2nd return")
  h.assertEq(corrupt, "{not json", "decode returns the raw corrupt bytes verbatim")
  h.assertNil(next(st2.snapshots), "decode(corrupt) 1st return is empty_state")

  -- string-key discipline: a non-string id must not error and keys by tostring(id) (Pitfall 5)
  local numkey = S.merge_save(S.empty_state(), 7, { name = "N", fade = 0, members = {} })
  h.assertTrue(numkey.snapshots["7"] ~= nil, "merge_save keys by tostring(id) (string key)")
end)

-- 2. BOUNDARY SHELL — opt-in in-memory GlobalVars mock; teardown-paired.
h.run("store boundary: lazy-init/round-trip/delta/delete/corrupt/clear (PER-01..04)", function()
  local S = h.loadModule("store.lua")

  -- lazy init: absent key → empty state AND load writes NOTHING (PER-04)
  h.withGlobalVarsMock(nil, function(store)
    local st = S.load()
    h.assertNil(next(st.snapshots), "load() on absent key → empty snapshots")
    h.assertNil(store["Snapshots"], "load() never writes (lazy init) — key stays nil")
  end)

  -- round-trip: save stores a JSON STRING (PER-01) and load reads it back (PER-02 proxy)
  h.withGlobalVarsMock(nil, function(store)
    S.save("id-A", { name = "Verse", fade = 3, members = {} })
    h.assertEq(type(store["Snapshots"]), "string", "stored value is a JSON string, never a table")
    h.assertEq(S.load().snapshots["id-A"].name, "Verse", "load() reads back the saved id")
  end)

  -- delta / no-clobber: two saves preserve BOTH ids (re-read-before-write, PER-03)
  h.withGlobalVarsMock(nil, function(store)
    S.save("peer-B", { name = "Chorus", fade = 0, members = {} })
    S.save("mine-A", { name = "Solo", fade = 1, members = {} })
    local snaps = S.load().snapshots
    h.assertTrue(snaps["peer-B"] ~= nil, "PER-03: peer id preserved across a second save")
    h.assertTrue(snaps["mine-A"] ~= nil, "PER-03: own id present")
  end)

  -- delete: removes only the targeted id; key stays a JSON string
  h.withGlobalVarsMock(nil, function(store)
    S.save("peer-B", { name = "Chorus", fade = 0, members = {} })
    S.save("mine-A", { name = "Solo", fade = 1, members = {} })
    S.delete("peer-B")
    local snaps = S.load().snapshots
    h.assertNil(snaps["peer-B"], "delete removes the targeted id")
    h.assertTrue(snaps["mine-A"] ~= nil, "delete leaves the other id")
    h.assertEq(type(store["Snapshots"]), "string", "key still a JSON string after delete")
  end)

  -- corrupt: a garbage blob degrades to empty AND preserves raw bytes to Snapshots_bak (PER-04)
  h.withGlobalVarsMock({ Snapshots = "{garbage" }, function(store)
    local st = S.load()
    h.assertNil(next(st.snapshots), "corrupt blob → empty snapshots (no crash)")
    h.assertEq(store["Snapshots_bak"], "{garbage", "corrupt raw bytes preserved to Snapshots_bak")
  end)

  -- clear: delete-all path removes the key
  h.withGlobalVarsMock(nil, function(store)
    S.save("id-A", { name = "Verse", fade = 3, members = {} })
    S.clear()
    h.assertNil(store["Snapshots"], "clear() removes the Snapshots key")
  end)
end)

-- 3. WRITE-PATH READ-FAILURE GUARD (WR-01) + corrupt NOTIFY (IN-01)
h.run("store: transient read failure on save/delete does NOT clobber peers (WR-01)", function()
  local S = h.loadModule("store.lua")

  -- Intact peer blob on disk; a transient GetVar hiccup must abort the write,
  -- leaving the peer bytes untouched (the inverse would be silent data loss).
  local peers = S.encode({ version = 1, snapshots = { ["peer-A"] = { name = "A" } } })
  h.withGlobalVarsMock({ Snapshots = peers }, function(store)
    _G.GetVar = function() error("transient load-race") end   -- read fails, bytes still on disk
    local ok = S.save("mine-B", { name = "B" })
    h.assertEq(ok, false, "save returns false on a failed read")
    h.assertEq(store["Snapshots"], peers, "on-disk blob unchanged — peers preserved")
  end)

  h.withGlobalVarsMock({ Snapshots = peers }, function(store)
    _G.GetVar = function() error("transient load-race") end
    local ok = S.delete("peer-A")
    h.assertEq(ok, false, "delete returns false on a failed read")
    h.assertEq(store["Snapshots"], peers, "on-disk blob unchanged on delete read-failure")
  end)
end)

h.run("store: corrupt blob fires the sysmon notify (IN-01)", function()
  local S = h.loadModule("store.lua")
  h.withGlobalVarsMock({ Snapshots = "{garbage" }, function(store)
    h.withPrintfCapture(function(msgs)
      local st = S.load()
      h.assertNil(next(st.snapshots), "corrupt → empty")
      h.assertEq(store["Snapshots_bak"], "{garbage", "raw bytes preserved to Snapshots_bak")
      h.assertTrue(#msgs >= 1, "notify fired to sysmon on corrupt blob")
    end)
  end)
end)
