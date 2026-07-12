-- lib/search.lua (Snapshots.search) — the PURE live-search filter for the manager topbar.
--
-- Drives BOTH panes from one query string:
--   * filter_rows(query, rows)     → the pane-3 (Object) row subset that matches
--   * category_counts(query, rows) → { [category] = match-count } for pane-2 dim/hide
--
-- Matching is a PLAIN, case-insensitive substring test over each row's label+addr haystack
-- (find(q, 1, true) — the `true` disables Lua patterns, so a query like "a.b" matches the
-- literal "a.b", never "aXb"). An empty/nil query means "no filter" — filter_rows returns the
-- input array unchanged and category_counts reports every row as a match.
--
-- BOUNDARY DISCIPLINE (boundary rule): PURE — this module NEVER reaches an MA3 global
-- (Cmd/Obj/Root/GlobalVars). The off-console harness leaves those undefined and crashes on a
-- violation. Input rows are never mutated. Global-namespace pattern; `return M` for tests.

Snapshots = Snapshots or {}   -- idempotent bootstrap (NEVER `= {}` — wipes siblings)
local M = {}
Snapshots.search = M

-- Normalize a query to a lowercased plain-substring needle, or nil when empty/blank.
local function needle(query)
  if query == nil then return nil end
  local q = tostring(query):lower()
  if q == "" then return nil end
  return q
end

-- The per-row haystack: label + addr, lowercased. Built inline; the input row is never mutated.
local function haystack(row)
  return (tostring(row.label or "") .. " " .. tostring(row.addr or "")):lower()
end

-- The row's category bucket for pane-2 counting: prefer an explicit .category, else .type.
local function categoryOf(row)
  return row.category or row.type
end

-- ── filter_rows(query, rows) -> array ──────────────────────────────────────
-- Empty/nil query → the SAME input array (no filter, no copy). Otherwise a NEW array holding
-- only the rows whose label+addr haystack contains the query as a plain substring.
function M.filter_rows(query, rows)
  rows = rows or {}
  local q = needle(query)
  if q == nil then return rows end
  local out = {}
  for _, row in ipairs(rows) do
    if haystack(row):find(q, 1, true) then
      out[#out + 1] = row
    end
  end
  return out
end

-- ── category_counts(query, rows) -> { [category] = count } ─────────────────
-- Counts, per category bucket, how many rows match the query. Empty/nil query → every row
-- counts (full per-category totals). Rows with no category are ignored. Deterministic; nil/{}
-- guarded.
function M.category_counts(query, rows)
  rows = rows or {}
  local q = needle(query)
  local counts = {}
  for _, row in ipairs(rows) do
    local cat = categoryOf(row)
    if cat ~= nil then
      if q == nil or haystack(row):find(q, 1, true) then
        counts[cat] = (counts[cat] or 0) + 1
      end
    end
  end
  return counts
end

return M
