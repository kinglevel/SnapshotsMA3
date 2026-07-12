-- tests/test_monitor.lua — System Monitor ring buffer (UI-03, T-09-04/05).
-- Proves push() appends + drops oldest beyond CAP, list() returns a COPY
-- oldest->newest that a caller can mutate freely, nil/number coerce to string,
-- and clear() empties. No process-exit here (Pitfall 8 — run_all owns it).
-- Each buffer-inspecting block re-loads the module and clear()s for a known-empty
-- start (Pitfall 3: the namespace singleton persists across dofiled test files).
local h = dofile((debug.getinfo(1,"S").source:sub(2):match("(.*/)") or "./") .. "helpers.lua")

-- Load the root entry file so Snapshots.log (the dispatch/arg-echo notify seam) is
-- defined. The entry is MA-free at load (varargs are nil under dofile, no console
-- reach) and `return Main` is ignored — we only want the Snapshots.log definition.
local HERE = (debug.getinfo(1,"S").source:sub(2):match("(.*/)") or "./")
local function loadEntry() return dofile(HERE .. "../Snapshots.lua") end

h.run("monitor push/list basic + attach + CAP field", function()
  local Mon = h.loadModule("monitor.lua")
  Mon.clear()

  -- CAP is a readable field, default 8
  h.assertEq(Mon.CAP, 8, "Monitor.CAP default 8")

  -- fresh module (after clear) lists empty
  h.assertEq(#Mon.list(), 0, "cleared buffer lists {}")

  -- push returns new length; single push -> {"a"}
  h.assertEq(Mon.push("a"), 1, "push returns #buffer == 1")
  local l = Mon.list()
  h.assertEq(#l, 1, "list length 1 after one push")
  h.assertEq(l[1], "a", "list[1] == 'a'")

  -- module attaches under the namespace key
  h.assertTrue(_G.Snapshots.monitor == Mon, "Snapshots.monitor == returned table")
end)

h.run("monitor CAP overflow drops oldest, keeps newest last", function()
  local Mon = h.loadModule("monitor.lua")
  Mon.clear()

  -- push 9 lines into a CAP=8 buffer
  for i = 1, 9 do Mon.push("line" .. i) end
  local l = Mon.list()
  h.assertEq(#l, 8, "buffer bounded at CAP=8 after 9 pushes")
  h.assertEq(l[1], "line2", "oldest (line1) dropped -> index 1 is line2")
  h.assertEq(l[8], "line9", "newest (line9) kept at last index")
end)

h.run("monitor list() order is oldest->newest", function()
  local Mon = h.loadModule("monitor.lua")
  Mon.clear()
  Mon.push("first")
  Mon.push("second")
  Mon.push("third")
  local l = Mon.list()
  h.assertEq(l[1], "first",  "index 1 == oldest")
  h.assertEq(l[2], "second", "index 2 == middle")
  h.assertEq(l[3], "third",  "index #== newest")
end)

h.run("monitor list() returns a COPY (mutation-safe)", function()
  local Mon = h.loadModule("monitor.lua")
  Mon.clear()
  Mon.push("x")
  Mon.push("y")
  local l1 = Mon.list()
  -- corrupt the returned table
  l1[1] = "HACKED"
  l1[3] = "EXTRA"
  table.remove(l1, 2)
  -- a subsequent list() is unaffected
  local l2 = Mon.list()
  h.assertEq(#l2, 2, "live buffer unchanged after mutating a returned copy")
  h.assertEq(l2[1], "x", "buffer[1] still 'x' after copy mutated")
  h.assertEq(l2[2], "y", "buffer[2] still 'y' after copy mutated")
  -- the two calls return DISTINCT tables
  h.assertTrue(l1 ~= l2, "each list() returns a distinct table")
end)

h.run("monitor push coerces nil->'' and number->string (no nil holes)", function()
  local Mon = h.loadModule("monitor.lua")
  Mon.clear()
  h.assertEq(Mon.push(nil), 1, "push(nil) still appends (length 1)")
  h.assertEq(Mon.push(123), 2, "push(123) appends (length 2)")
  local l = Mon.list()
  h.assertEq(l[1], "",    "push(nil) stored empty string, not a nil hole")
  h.assertEq(l[2], "123", "push(123) stored tostring(123)")
end)

h.run("monitor clear() empties the buffer", function()
  local Mon = h.loadModule("monitor.lua")
  Mon.push("a")
  Mon.push("b")
  h.assertTrue(#Mon.list() >= 2, "buffer has entries before clear")
  Mon.clear()
  h.assertEq(#Mon.list(), 0, "clear() -> list() == {}")
end)

-- UI-03 two-seam fan-out: BOTH notify seams (Snapshots.log dispatch/arg-echo seam
-- AND Ma3.notify RCL-06 skip-and-notify seam) push their display line to the strip
-- AND Printf it, with EXACTLY ONE "Snapshots: " prefix each (no double prefix — the
-- ma3 msg is already prefixed, so ma3 must NOT cross-route through Snapshots.log).
h.run("monitor two-seam fan-out: Snapshots.log + Ma3.notify feed the strip AND Printf (single prefix)", function()
  local Mon = h.loadModule("monitor.lua")
  Mon.clear()
  -- Ma3.notify lives in lib/ma3.lua; loading it under the BARE harness attaches
  -- Snapshots.ma3.notify (pure-side seam — Printf is left undefined by default).
  h.loadModule("ma3.lua")
  loadEntry()                                  -- defines Snapshots.log

  h.withPrintfCapture(function(msgs)
    -- Snapshots.log builds the "Snapshots: " prefix ONCE.
    Snapshots.log("hello")
    -- Ma3.notify receives an ALREADY-prefixed string (as ma3 emits it in-repo).
    Snapshots.ma3.notify("Snapshots: skip page 3.5")

    local l = Mon.list()
    h.assertEq(#l, 2, "both seams pushed one line each → buffer length 2")
    h.assertEq(l[1], "Snapshots: hello", "log seam pushed a single-prefixed 'Snapshots: hello'")
    h.assertEq(l[2], "Snapshots: skip page 3.5",
      "ma3 seam pushed the already-prefixed line verbatim (NO double 'Snapshots: Snapshots:')")
    h.assertTrue(not l[2]:find("Snapshots: Snapshots:", 1, true),
      "no double 'Snapshots: ' prefix on the ma3 seam line")

    -- Printf ALSO fired for each seam (call text UNCHANGED — the harness mock joins
    -- format args with a tab rather than formatting, so match on the message substring).
    h.assertEq(#msgs, 2, "both seams Printf'd exactly once each")
    h.assertTrue(msgs[1]:find("hello", 1, true) ~= nil, "log seam Printf carried the message")
    h.assertEq(msgs[2], "Snapshots: skip page 3.5",
      "ma3 seam Printf(msg) carried the already-prefixed string verbatim (single arg)")
  end)
end)

-- Call-time-guarded degrade: with Snapshots.monitor ABSENT, both seams must still
-- Printf and never error (pcall + `if Snapshots.monitor` guard — T-09-10).
h.run("monitor absent: log/notify still Printf and do not error (guarded degrade)", function()
  h.loadModule("ma3.lua")
  loadEntry()                                  -- defines Snapshots.log
  local saved = Snapshots.monitor
  Snapshots.monitor = nil                      -- simulate load race / off-desk
  local ok = pcall(function()
    h.withPrintfCapture(function(msgs)
      Snapshots.log("still logs")
      Snapshots.ma3.notify("Snapshots: still notifies")
      h.assertTrue(msgs[1]:find("still logs", 1, true) ~= nil, "log Printf survives absent monitor")
      h.assertEq(msgs[2], "Snapshots: still notifies", "notify Printf survives absent monitor")
    end)
  end)
  Snapshots.monitor = saved                    -- restore the singleton for later blocks
  h.assertTrue(ok, "both seams degrade gracefully when Snapshots.monitor is nil")
end)
