-- tests/test_search.lua — pure live-search filter (Snapshots.search).
-- Covers: empty query = no filter, case-insensitive substring match, PLAIN (non-pattern)
-- match, and per-category counts. Also a purity smoke — the harness leaves MA3 globals
-- undefined, so any accidental reach would crash this dofile. No os.exit here.
local h = dofile((debug.getinfo(1,"S").source:sub(2):match("(.*/)") or "./") .. "helpers.lua")

local function rows()
  return {
    { key = "e1", label = "Verse Master",   addr = "13.101", type = "executor" },
    { key = "e2", label = "Chorus",         addr = "13.102", type = "executor" },
    { key = "g1", label = "Front Wash",     addr = "Group 1", type = "group" },
    { key = "p1", label = "Solo a.b look",  addr = "Preset 2.1", type = "preset" },
  }
end

h.run("search loads pure (no MA3 globals) + attaches to namespace", function()
  local M = h.loadModule("search.lua")
  h.assertTrue(type(M) == "table", "returns a module table")
  h.assertTrue(type(M.filter_rows) == "function", "exposes filter_rows")
  h.assertTrue(type(M.category_counts) == "function", "exposes category_counts")
  h.assertTrue(_G.Snapshots.search == M, "attaches Snapshots.search")
end)

h.run("filter_rows: empty query returns the full set unchanged", function()
  local M = h.loadModule("search.lua")
  local r = rows()
  h.assertEq(M.filter_rows("", r), r, "empty string => same array (no filter)")
  h.assertEq(M.filter_rows(nil, r), r, "nil => same array (no filter)")
  h.assertEq(#M.filter_rows("", r), 4, "all four rows present")
end)

h.run("filter_rows: case-insensitive substring on label AND addr", function()
  local M = h.loadModule("search.lua")
  local out = M.filter_rows("verse", rows())
  h.assertEq(#out, 1, "one label match for 'verse'")
  h.assertEq(out[1].key, "e1", "matched the Verse Master row")
  -- addr is part of the haystack too
  local byAddr = M.filter_rows("group 1", rows())
  h.assertEq(#byAddr, 1, "matched via addr 'Group 1'")
  h.assertEq(byAddr[1].key, "g1", "matched the group row by address")
end)

h.run("filter_rows: plain (non-pattern) match — 'a.b' is literal, not a wildcard", function()
  local M = h.loadModule("search.lua")
  -- "a.b" as a Lua pattern would match "aXb"; plain find must only match the literal "a.b".
  local hit = M.filter_rows("a.b", rows())
  h.assertEq(#hit, 1, "'a.b' matches the literal 'Solo a.b look'")
  h.assertEq(hit[1].key, "p1", "matched the preset row literally")
  local miss = M.filter_rows("axb", rows())
  h.assertEq(#miss, 0, "'axb' does NOT match (proves plain, not pattern)")
end)

h.run("filter_rows: does not mutate input rows", function()
  local M = h.loadModule("search.lua")
  local r = rows()
  M.filter_rows("verse", r)
  h.assertEq(#r, 4, "input array length unchanged")
  h.assertEq(r[1].label, "Verse Master", "input row unchanged")
end)

h.run("category_counts: per-category match counts (empty = full totals)", function()
  local M = h.loadModule("search.lua")
  local full = M.category_counts("", rows())
  h.assertEq(full.executor, 2, "two executor rows total")
  h.assertEq(full.group, 1, "one group row total")
  h.assertEq(full.preset, 1, "one preset row total")

  local q = M.category_counts("chorus", rows())
  h.assertEq(q.executor, 1, "only Chorus matches under executor")
  h.assertNil(q.group, "no group match => absent/zero")
  h.assertNil(q.preset, "no preset match => absent/zero")
end)
