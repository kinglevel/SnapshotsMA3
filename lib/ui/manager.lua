-- lib/ui/manager.lua (Snapshots.ui.manager) — the CONSOLE-ONLY 3-pane manager render.
--
-- Mounts the native ScreenOverlay → BaseInput window (UI-01) and wires its signalTable
-- handlers. Follows the standard MA3 chrome mount, the styling helper trio, the ContentDriven
-- scroll stack and the in-place row-recolor.
--
-- Pane 1 (Snapshot) is LIVE: a scrollable list from Snapshots.manager.list_rows, a ＋New /
-- Rename… header and a Clear… / Delete… footer. Every button handler is a THIN ADAPTER —
-- read the widget → call the pure Snapshots.manager.* lifecycle (proven off-console in
-- Plan 02) → repaint. This file holds ZERO lifecycle logic; any direct persistence write or
-- model mutation here would be a seam leak (RESEARCH anti-pattern). Panes 2/3 (Type/Object) are read-only
-- scaffolds until Phase 8.
--
-- Registry safety (UI-04): ONLY the 07-UI-SPEC verified appendable classes are :Append()ed
-- (BaseInput/UILayoutGrid/DialogFrame/TitleBar/TitleButton/CloseButton/ScrollContainer/ScrollBox/UIObject/
-- Button); NONE of the 9 documented crashers ever appear.
--
-- Global-namespace multi-file pattern; siblings resolved at CALL time. Varargs captured at
-- FILE SCOPE — the file MUST NOT touch any MA3 global at load time, only inside function
-- bodies, every reach pcall-wrapped. NEVER loaded by the host harness (it reaches
-- ScreenOverlay; the boundary would crash on it) — grep-verified here, screenshot-verified
-- onPC in Plan 05.

Snapshots = Snapshots or {}
Snapshots.ui = Snapshots.ui or {}
local M = {}
Snapshots.ui.manager = M

-- Retained per-interaction handles. _rowBtns/_rowStripes map a snapshot id → its clickable
-- backplate / 4px selection-stripe Button so a select recolors the old/new row IN PLACE
-- (no list rebuild, no flash). _selected is the current row id; _deps is the injected bag;
-- _ui caches the ScrollBox + footer/header action buttons for enable-state + list refresh.
M._rowBtns    = {}
M._rowStripes = {}
M._rowBadges  = {}   -- id → the assigned/stored badge cell, refreshed in place on a tick
M._selected   = nil
M._deps       = nil
M._ui         = {}

-- Phase-8 (panes 2/3) cross-pane state + retained handles for in-place recolor.
-- _selectedType is the current category ("executor"/"group"/"master"); _objCursor is
-- the pane-3 browse page cursor; _typeRowBtns/_typeCountCells map a category → its
-- pane-2 backplate / assigned-count cell; _objRows maps a row key → {fill,checkbox,
-- numeric,backplate} for a per-tick recolor; _objRefs maps a row key → the real schema
-- ref the tick handler passes to Snapshots.assign.*.
M._selectedType   = nil
M._objCursor      = { page = 1 }
M._typeRowBtns    = {}
M._typeCountCells = {}
M._objRows        = {}
M._objRefs        = {}

-- Phase-9 playback state (UI-owned, NOT persisted here): _fadeSeconds is the next-recall
-- fade override the bar passes to the tested arg surface; _snapMode is the global Fade/Snap
-- toggle (RCL-04) — true ⇒ Snap ⇒ fade=0. Defaults: 3.0s, Fade mode. Snap_Select seeds
-- _fadeSeconds from the selected snapshot's stored default (fallback 3.0).
M._fadeSeconds    = 3.0
M._snapMode       = false

-- Topbar live-search query (lowercased; "" or nil ⇒ no filter). Set by Snap_Search, read by
-- M.refreshObjects (pane 3 row filter) + M.refreshTypeFilter (pane 2 dim). Never persisted.
M._query          = ""

-- Entry-point varargs at FILE SCOPE (nil under host tests).
local signalTable = select(3, ...)
local my_handle   = select(4, ...)

-- ── vetted stock TextColor refs (strings — TextColor accepts a named-string ref) ──
local TXT = { bright = "Global.Bright", dim = "Global.PartlySelected" }

-- ── theme ref helpers (BackColor takes ONLY a ColorGroup ref OBJECT, never a hex) ──
-- themeRef returns the cached SnapshotsColors ColorGroup ref for a role (nil off-desk /
-- pre-install). applyBg assigns it to a widget's BackColor inside a pcall — a nil ref or an
-- absent theme leaves the widget default; a string would silently no-op so we never pass one.
local function themeRef(role)
  local r
  pcall(function() r = Snapshots.ui.theme and Snapshots.ui.theme.ref(role) end)
  return r
end
local function applyBg(widget, role)
  if not widget then return end
  pcall(function() local r = themeRef(role); if r then widget.BackColor = r end end)
end

-- dim TEXT color. The stock "Global.PartlySelected" ref MA3 renders as ORANGE (hard to read
-- on the dark surfaces — onPC feedback). Use the theme's grey `textDim` swatch (61666E) for all
-- sub-lines / badges / counts / empty states; fall back to the stock ref only pre-install/off-desk.
local function dimc() return themeRef("textDim") or "Global.PartlySelected" end

-- ── styling helper trio ───────────────────────────────────────────────────────
-- setCols sizes columns via the ItemCollectColumns setter (grid[c][r] does NOT size
-- columns); rowH fixes a row height; cell appends the only label class (UIObject);
-- iconBtn appends a Button wired with PluginComponent + a Clicked STRING signal.
local function setCols(g, specs)
  pcall(function()
    for _, c in ipairs(g:Children()) do
      if c:GetClass() == "ItemCollectColumns" then
        local items = c:Children()
        for i, sp in ipairs(specs) do
          if items[i] then
            items[i].SizePolicy = sp.w and "Fixed" or "Stretch"
            if sp.w then items[i].Size = tostring(sp.w) end
          end
        end
        return
      end
    end
  end)
end
local function rowH(g, i, px) pcall(function() g[1][i].SizePolicy="Fixed"; g[1][i].Size=tostring(px) end) end

local function cell(parent, span, text, font, align, color)
  local u = parent:Append("UIObject"); u.Anchors = span
  if text then u.Text = text end
  u.Font = font or "Regular16"
  pcall(function()
    u.TextalignmentH = align or "Left"; u.TextalignmentV = "Center"
    u.HasHover = "No"; u.Focus = "Never"
    if color then u.TextColor = color end
  end)
  return u
end

local function iconBtn(parent, span, icon, text, signal, opts)
  opts = opts or {}
  local b = parent:Append("Button"); b.Anchors = span
  if text then b.Text = text end
  b.Font = opts.font or "Regular16"; b.TextalignmentH = opts.align or "Center"
  if icon then pcall(function() b.Icon = icon; b.IconAlignmentH = opts.iconH or "Left"; b.IconAlignmentV = "Center" end) end
  if signal then b.PluginComponent = my_handle; b.Clicked = signal else pcall(function() b.Enabled = "No" end) end
  if opts.text then pcall(function() b.TextColor = opts.text end) end
  return b
end

-- ── styleRow — resting vs selected row surface (07-UI-SPEC selection cue) ──────
-- Backplate rests on the `row` surface / raises to `hover` when selected; the 4px stripe
-- rests on `surface` / lights `cyan` when selected (the sketch's inset cyan selection stripe).
-- Every BackColor apply is a pcall-guarded ColorGroup ref — never a hex string.
local function styleRow(backplate, stripe, selected)
  if backplate then
    pcall(function() local r = selected and themeRef("hover") or themeRef("row"); if r then backplate.BackColor = r end end)
  end
  if stripe then
    pcall(function() local r = selected and themeRef("cyan") or themeRef("surface"); if r then stripe.BackColor = r end end)
  end
end

-- ── nameOf — read-only lookup of a snapshot name for the prompt copy ──────────
-- Reads deps.store.load() (a READ for rendering — sanctioned) and indexes the plain
-- table; never mutates. Used to name the snapshot in the Confirm / TextInput dialogs.
local function nameOf(id)
  local nm = ""
  pcall(function()
    local deps = M._deps
    local coll = deps and deps.store.load()
    local snap = coll and coll.snapshots and coll.snapshots[tostring(id)]
    if snap then nm = snap.name or "" end
  end)
  return nm
end

-- ── setActionState — selection-gated buttons enabled only with a selection ────
-- Pane-1 Rename/Clear/Delete PLUS the four selection-gated playback-bar buttons
-- (Recall/Store/Breakdown/Default-fade). The Fade-value button and the Fade/Snap
-- toggle are GLOBAL settings (UI-02/RCL-04) and are NEVER disabled here.
local function setActionState()
  local on = M._selected ~= nil
  for _, b in ipairs({ M._ui.dupBtn, M._ui.renameBtn, M._ui.clearBtn, M._ui.deleteBtn,
                       M._ui.recallBtn, M._ui.storeBtn, M._ui.breakdownBtn, M._ui.defFadeBtn }) do
    if b then pcall(function() b.Enabled = on and "Yes" or "No" end) end
  end
end

-- ── buildRow — one snapshot row: backplate + 4px stripe + name/sub-line + badge ─
-- Row grid columns are 4px | 1fr | 46px. The full-span Button backplate carries the click
-- (id encoded in .Name = "SnapRow_<id>", recovered by regex in Snap_Select — via .Name only,
-- never a per-object metadata field); the stripe/name/sub/badge sit ON TOP (Focus="Never")
-- so clicks fall through to the backplate.
local function buildRow(grid, i, r, selectedId)
  local top = i - 1
  rowH(grid, i, 44)   -- FIXED row height — without it, N rows stretch to fill the box
  -- col 0: 4px selection stripe (disabled, non-interactive) — its OWN column, NEVER over the button
  local stripe = grid:Append("Button"); stripe.Anchors = { left = 0, right = 0, top = top, bottom = top }
  stripe.Text = ""; pcall(function() stripe.Enabled = "No"; stripe.HasHover = "No"; stripe.Focus = "Never" end)
  -- col 1: THE clickable row Button — its OWN .Text carries the label (row idiom).
  -- It MUST be the topmost element in its column: overlaying a UIObject label here would win the
  -- MA3 hit-test (GetUIObjectAtPosition returns topmost; Focus="Never" does NOT pass clicks through)
  -- and Snap_Select would never fire — the onPC row-select bug. Fold the sub-line inline.
  local label = r.name or ""
  if r.sub_line and r.sub_line ~= "" then label = label .. "   ·  " .. r.sub_line end
  local bp = grid:Append("Button"); bp.Anchors = { left = 1, right = 1, top = top, bottom = top }
  bp.Text = "  " .. label; bp.Name = "SnapRow_" .. tostring(r.id)
  bp.Font = "Regular16"; pcall(function() bp.TextalignmentH = "Left"; bp.TextalignmentV = "Center" end)
  pcall(function() bp.TextColor = (r.sub_line == "breakdown") and (themeRef("amber") or TXT.bright) or TXT.bright end)
  bp.PluginComponent = my_handle; bp.Clicked = "Snap_Select"
  -- col 2: assigned/stored badge — separate, non-overlapping column (UIObject, non-clickable)
  local badge = cell(grid, { left = 2, right = 2, top = top, bottom = top },
    tostring(r.assigned) .. "/" .. tostring(r.stored), "Regular14", "Right", dimc())
  -- retain handles + paint resting/selected state
  M._rowBtns[r.id] = bp
  M._rowStripes[r.id] = stripe
  M._rowBadges[r.id] = badge
  styleRow(bp, stripe, r.id == selectedId)
end

-- ── renderList — rebuild ONLY the pane-1 list body from list_rows (row SET change) ─
-- Clears the retained ScrollBox and re-appends the ContentDriven grid. Called on open and
-- from M.refresh after a create/rename/clear/delete. A SELECT never routes here (it recolors
-- in place). Empty collection → a single dim centered empty-state message.
local function renderList(deps)
  local box = M._ui and M._ui.listBox
  if not box then return end
  pcall(function() box:ClearUIChildren() end)
  M._rowBtns, M._rowStripes, M._rowBadges = {}, {}, {}

  local rows = {}
  pcall(function() rows = Snapshots.manager.list_rows(deps.store.load()) or {} end)
  local count = #rows

  local grid = box:Append("UILayoutGrid"); grid.ContentDriven = true
  grid.Columns, grid.Rows = 3, math.max(count, 1)
  setCols(grid, { { w = 4 }, {}, { w = 46 } })

  if count == 0 then
    rowH(grid, 1, 44)
    cell(grid, { left = 0, right = 2, top = 0, bottom = 0 },
      "No snapshots yet — press ＋New to create one.", "Regular14", "Center", dimc())
  else
    for i, r in ipairs(rows) do buildRow(grid, i, r, M._selected) end
  end

  M._ui.listGrid = grid
  pcall(function() box:WaitInit(2) end); pcall(function() grid:WaitInit(2) end)
end

-- ── titlebar — TitleBar → TitleButton (the DRAGGABLE grab handle) + CloseButton ─
-- The title MUST be a TitleButton, not a plain UIObject label: TitleButton is the native
-- draggable grab handle that lets the operator move the window — a UIObject label is static
-- and the window won't drag (onPC feedback). TitleButton is verified [LIVE] appendable and is
-- distinct from the exec-title crasher variant (which needs a SpecialExecIndex bound at append).
-- Canonical MA3 recipe (titlebar): TitleButton at Anchors "0,0" gets NO width (fills
-- the default-Stretch col 0); size the CLOSE column via tb[2][2] (indexer is lenient on the row).
-- CloseButton MUST be a TitleBar child (append fails standalone).
local function titlebar(root, text)
  local tb = root:Append("TitleBar"); tb.Anchors = "0,0"; tb.Columns, tb.Rows = 2, 1
  pcall(function() tb.Texture = "corner2" end)
  local tt = tb:Append("TitleButton"); tt.Anchors = "0,0"
  tt.Text = text; pcall(function() tt.Texture = "corner1" end)          -- draggable; NO width (fills Stretch col 0)
  local cb = tb:Append("CloseButton"); cb.Anchors = "1,0"
  pcall(function() cb.Texture = "corner2" end)
  cb.PluginComponent = my_handle; cb.Clicked = "OnClose"
  pcall(function() tb[2][2].SizePolicy = "Fixed"; tb[2][2].Size = "50" end)  -- size the CLOSE column
end

-- ── paneFrame — a DialogFrame panel in one column of the 3-pane grid ──────────
local function paneFrame(host, cellIdx)
  local fr = host:Append("DialogFrame")
  fr.Anchors = { left = cellIdx - 1, right = cellIdx - 1, top = 0, bottom = 0 }
  fr.H, fr.W = "100%", "100%"
  pcall(function() fr.Margin = "3,3,3,3"; fr.Texture = "frame15" end)
  applyBg(fr, "surface")
  return fr
end

-- ── barFrame — the SAME outlined DialogFrame card as paneFrame, but anchored to a
-- ROW cell (top/bottom = cellIdx-1) instead of a column cell. Used to wrap the two
-- bottom bars (playback toolbar, System Monitor strip) so they read as cards that
-- match the 3 panes rather than floating slabs. Mirror paneFrame exactly.
local function barFrame(host, cellIdx)
  local fr = host:Append("DialogFrame")
  fr.Anchors = { left = 0, right = 0, top = cellIdx - 1, bottom = cellIdx - 1 }
  fr.H, fr.W = "100%", "100%"
  pcall(function() fr.Margin = "3,3,3,3"; fr.Texture = "frame15" end)
  applyBg(fr, "surface")
  return fr
end

-- ══ PHASE-8 panes 2 (Type) + 3 (Object) — LIVE renders over Snapshots.assign.* ══
-- THIN adapters: read a widget → call the PURE Snapshots.assign.* view-model / mutator
-- → persist via the INJECTED deps.store.save (peer-safe delta) → repaint. ZERO lifecycle
-- or model logic lives here. Only 07/08-UI-SPEC verified classes are appended (UILayoutGrid/
-- DialogFrame/ScrollContainer/ScrollBox/UIObject/Button/CheckBox) — never a bound value-
-- fader class, never a crasher. The value bar is the COMPOSED fader-bar (faderTrack + fill).

-- Category → tag/fill swatch role + display label (fixed pane-2 order).
local TYPE_ORDER  = { "executor", "sequence", "preset", "group", "master" }
local TYPE_LABELS = { executor = "Executor masters", sequence = "Sequences", preset = "Presets",
                      group = "Group masters", master = "Special masters" }
-- The 5 types grouped under section dividers: EXEC (fader view) · DATAPOOL (pool objects that
-- live inside a datapool) · GLOBALS (show-wide masters). Each group gets a thin 1px divider + title.
local TYPE_GROUPS = {
  { title = "EXEC",     types = { "executor" } },
  { title = "DATAPOOL", types = { "sequence", "preset", "group" } },
  { title = "GLOBALS",  types = { "master" } },
}
local function catSwatch(cat)
  if cat == "group" then return "chipGroup"
  elseif cat == "master" then return "chipMaster"
  elseif cat == "sequence" then return "chipSequence"
  elseif cat == "preset" then return "chipPreset"
  else return "chipExec" end
end

-- Pool types honour the datapool selector (their objects live inside a datapool). Executor is a
-- fader view (spans pages) and Special masters are global — neither is datapool-scoped.
local function isPoolType(t) return t == "sequence" or t == "preset" or t == "group" end

-- Label + enabled state for the pane-3 header datapool selector. nil M._datapool = all datapools.
local function dpLabel()
  if not isPoolType(M._selectedType) then return "OBJECT", false end
  if M._datapool == nil then return "▾ All datapools", true end
  local nm = "▾ Datapool " .. tostring(M._datapool)
  pcall(function()
    for _, d in ipairs(Snapshots.ma3.datapools() or {}) do
      if d.index == M._datapool then nm = "▾ " .. tostring(d.name) end
    end
  end)
  return nm, true
end

-- pane-3 browse: rows per page (paginates a very large pool — ASGN-04).
local OBJ_PAGE_SIZE = 40

-- currentSnap — READ the selected snapshot table for rendering / mutation (sanctioned
-- read; never a write here). nil when no selection or off-desk.
local function currentSnap()
  local snap
  pcall(function()
    local deps = M._deps
    local coll = deps and deps.store.load()
    snap = coll and coll.snapshots and coll.snapshots[tostring(M._selected)]
  end)
  return snap
end

-- memberValue — the kept 0..100 value of the member matching `key` (0 if absent).
local function memberValue(snap, key)
  local v = 0
  pcall(function()
    for _, m in ipairs((snap and snap.members) or {}) do
      if Snapshots.schema.key(m.ref) == key then v = m.value or 0; return end
    end
  end)
  return v
end

-- paintTick — the CheckBox colored-checked caveat (07-UI-SPEC HARD): a checked tick sets
-- BOTH BackColor AND ActiveBackColor to the cyan ref, else the checked box swaps to the
-- dark ActiveBackground and loses its color. Unchecked resets both to the resting `row`.
local function paintTick(cb, checked)
  if not cb then return end
  pcall(function()
    local r = checked and themeRef("cyan") or themeRef("row")
    if r then cb.BackColor = r; cb.ActiveBackColor = r end
  end)
end

-- updateSnapBadge — recompute the SELECTED snapshot's assigned/stored badge in pane 1 and
-- set it in place (no list rebuild). Called after a tick / bulk assign so pane 1 stays in sync
-- with pane 2/3 (otherwise the badge reads a stale 0/0 while "N assigned" already updated).
local function updateSnapBadge()
  local badge = M._rowBadges and M._selected and M._rowBadges[M._selected]
  if not badge then return end
  local assigned, stored = 0, 0
  pcall(function()
    local snap = currentSnap()
    for _, m in ipairs((snap and snap.members) or {}) do
      stored = stored + 1
      if m.assigned then assigned = assigned + 1 end
    end
  end)
  pcall(function() badge.Text = tostring(assigned) .. "/" .. tostring(stored) end)
end

-- setObjActionState — bulk footer enabled ONLY with a selected snapshot AND type; the
-- page-range prompt is executor-only (ASGN-05). Assign selection is DEFERRED (ASGN-03)
-- and left enabled to surface the deferred notify.
local function setObjActionState()
  local on = (M._selected ~= nil) and (M._selectedType ~= nil)
  if M._ui.assignAllBtn then pcall(function() M._ui.assignAllBtn.Enabled = on and "Yes" or "No" end) end
  if M._ui.assignNoneBtn then pcall(function() M._ui.assignNoneBtn.Enabled = on and "Yes" or "No" end) end
end

-- refreshTypeCounts — recompute the 3 pane-2 assigned counts and update the count cells
-- IN PLACE (no rebuild). Passes {} pool_counts (only the assigned tally is read here) so a
-- tick never triggers a console pool walk. Cyan text when assigned>0.
local function refreshTypeCounts()
  local snap = currentSnap()
  local rows = {}
  pcall(function() rows = Snapshots.assign.type_rows({}, snap, M._poolRefs) or {} end)
  for _, r in ipairs(rows) do
    local c = M._typeCountCells and M._typeCountCells[r.category]
    if c then
      pcall(function()
        c.Text = tostring(r.assigned) .. " assigned"
        c.TextColor = (r.assigned > 0) and (themeRef("cyan") or dimc()) or dimc()
      end)
    end
  end
end

-- buildTypeRow — one pane-2 category row into a 3-col grid (34px | 1fr | 96px), mirroring
-- the pane-1 buildRow idiom: a full-span Button backplate appended FIRST carries the click
-- (.Name="TypeRow_<cat>"), cells layer on top (tag Button / name+"N in show" / assigned count).
local function buildTypeRow(grid, i, r)
  local top = i - 1
  rowH(grid, i, 56)   -- FIXED row height; without it the 3 rows stretch huge
  -- col 0: colored category tag (non-interactive) — its OWN column, never over the button
  local tag = grid:Append("Button"); tag.Anchors = { left = 0, right = 0, top = top, bottom = top }
  tag.Text = ""; pcall(function() tag.Enabled = "No"; tag.HasHover = "No"; tag.Focus = "Never" end)
  applyBg(tag, catSwatch(r.category))
  -- col 1: THE clickable type Button (topmost in its column) — label + "(N in show)" as its OWN Text.
  -- Same rule as the snapshot row: an overlaid UIObject would swallow the click and Type_Select would
  -- never fire. Single line so the Button owns the whole hit-area.
  local bp = grid:Append("Button"); bp.Anchors = { left = 1, right = 1, top = top, bottom = top }
  bp.Text = "  " .. tostring(r.label) .. "    (" .. tostring(r.in_show) .. " in show)"
  bp.Name = "TypeRow_" .. tostring(r.category)
  bp.Font = "Regular16"; pcall(function() bp.TextalignmentH = "Left"; bp.TextalignmentV = "Center"; bp.TextColor = TXT.bright end)
  bp.PluginComponent = my_handle; bp.Clicked = "Type_Select"
  -- col 2: assigned count (separate column, non-clickable), cyan when > 0
  local countColor = (r.assigned > 0) and (themeRef("cyan") or dimc()) or dimc()
  local countCell = cell(grid, { left = 2, right = 2, top = top, bottom = top },
    tostring(r.assigned) .. " assigned", "Regular14", "Right", countColor)
  M._typeRowBtns[r.category]    = bp
  M._typeCountCells[r.category] = countCell
  styleRow(bp, nil, r.category == M._selectedType)
end

-- buildTypeDivider — a section header row: a small dim title over a thin 1px line, full width.
-- Groups the type rows into EXEC / DATAPOOL / GLOBALS (TYPE_GROUPS). Non-interactive.
local function buildTypeDivider(grid, i, title)
  rowH(grid, i, 22)
  local sub = grid:Append("UILayoutGrid"); sub.Anchors = { left = 0, right = 2, top = i - 1, bottom = i - 1 }
  sub.Columns, sub.Rows = 1, 2
  rowH(sub, 2, 1)
  -- title cell: set its OWN BackColor to black (a UIObject renders Text over its BackColor), so the
  -- text sits on black rather than the grey pane surface. A separate backfill behind did not composite.
  local t = cell(sub, { left = 0, right = 0, top = 0, bottom = 0 }, title, "Regular11", "Left", dimc())
  applyBg(t, "bg")
  -- an EXACT 1px line at the very bottom, on its own black-filled row so it reads cleanly
  local line = sub:Append("UIObject"); line.Anchors = { left = 0, right = 0, top = 1, bottom = 1 }
  pcall(function() line.HasHover = "No"; line.Focus = "Never" end)
  applyBg(line, "textDim")
end

-- buildPane2 — the LIVE Type pane: header + the 5 category rows grouped under EXEC / DATAPOOL /
-- GLOBALS dividers. Counts come from Snapshots.assign.type_rows; the pool reads are pcall-wrapped.
local function buildPane2(host, deps)
  local fr = paneFrame(host, 2)
  local wrap = fr:Append("UILayoutGrid"); wrap.Anchors = "0,0"; wrap.Columns, wrap.Rows = 1, 2
  rowH(wrap, 1, 26); pcall(function() wrap[1][2].SizePolicy = "Stretch" end)
  cell(wrap, { left = 0, right = 0, top = 0, bottom = 0 }, "TYPE", "Regular14", "Left", dimc())

  -- body: one 3-col grid (34px | 1fr | 96px). Rows = each group's divider + its type rows.
  local body = wrap:Append("UILayoutGrid"); body.Anchors = { left = 0, right = 0, top = 1, bottom = 1 }
  local totalRows = 0
  for _, g in ipairs(TYPE_GROUPS) do totalRows = totalRows + 1 + #g.types end
  body.Columns, body.Rows = 3, totalRows
  setCols(body, { { w = 34 }, {}, { w = 96 } })

  local snap = currentSnap()
  -- Walk every pool ONCE and cache the refs; counts + GUID-based categorisation both derive from
  -- these (avoids a second walk in pool_counts, and lets type_rows categorise by live pool).
  pcall(function()
    M._poolRefs = {
      executor = Snapshots.ma3.pool_objects("executor") or {},
      sequence = Snapshots.ma3.pool_objects("sequence") or {},
      preset   = Snapshots.ma3.pool_objects("preset")   or {},
      group    = Snapshots.ma3.pool_objects("group")    or {},
      master   = Snapshots.ma3.pool_objects("master")   or {},
    }
  end)
  local counts = {}
  for k, v in pairs(M._poolRefs or {}) do counts[k] = #v end
  local rows = {}
  pcall(function() rows = Snapshots.assign.type_rows(counts, snap, M._poolRefs) or {} end)
  local byCat = {}
  for _, r in ipairs(rows) do byCat[r.category] = r end

  M._typeRowBtns, M._typeCountCells = {}, {}
  local rowIdx = 1
  for _, g in ipairs(TYPE_GROUPS) do
    buildTypeDivider(body, rowIdx, g.title); rowIdx = rowIdx + 1
    for _, cat in ipairs(g.types) do
      local r = byCat[cat] or { category = cat, label = TYPE_LABELS[cat], in_show = 0, assigned = 0 }
      buildTypeRow(body, rowIdx, r); rowIdx = rowIdx + 1
    end
  end
end

-- buildObjRow — one pane-3 Object row into a 4-col grid (34px | 1fr | 78px | 34px):
-- colored tag · label+addr sub-line · composed fader-bar+numeric · CheckBox tick. Retains
-- {fill,checkbox,numeric,backplate} in M._objRows[key] for the in-place tick recolor.
local function buildObjRow(grid, i, r, swatch)
  local top = i - 1
  rowH(grid, i, 44)   -- FIXED row height — the CheckBox tick stays topmost/clickable
  -- resting row surface backplate (full span incl. the trailing gap); missing → red-tinted
  local bp = grid:Append("Button"); bp.Anchors = { left = 0, right = 4, top = top, bottom = top }
  bp.Text = ""; pcall(function() bp.Enabled = "No"; bp.HasHover = "No"; bp.Focus = "Never" end)
  applyBg(bp, r.state == "missing" and "red" or "row")
  -- colored tag (col 0), non-interactive
  local tag = grid:Append("Button"); tag.Anchors = { left = 0, right = 0, top = top, bottom = top }
  tag.Text = ""; pcall(function() tag.Enabled = "No"; tag.HasHover = "No"; tag.Focus = "Never" end)
  applyBg(tag, swatch)
  -- label (upper) + addr/short-guid (lower), col 1
  local tcol = grid:Append("UILayoutGrid"); tcol.Anchors = { left = 1, right = 1, top = top, bottom = top }
  tcol.Columns, tcol.Rows = 1, 2
  local labelTxt, labelColor = tostring(r.label or ""), TXT.bright
  if r.state == "missing" then
    labelTxt = labelTxt .. " · missing"; labelColor = themeRef("red") or TXT.bright
  end
  cell(tcol, { left = 0, right = 0, top = 0, bottom = 0 }, labelTxt, "Regular16", "Left", labelColor)
  cell(tcol, { left = 0, right = 0, top = 1, bottom = 1 },
    tostring(r.addr or r.key or ""), "Regular14", "Left", dimc())
  -- composed fader-bar + numeric (col 2): numeric (upper) over the track+fill (lower)
  local fcol = grid:Append("UILayoutGrid"); fcol.Anchors = { left = 2, right = 2, top = top, bottom = top }
  fcol.Columns, fcol.Rows = 1, 2
  local numTxt
  if r.state == "missing" then numTxt = "—"
  elseif r.state == "parked" then numTxt = tostring(r.value or 0) .. " parked"
  else numTxt = tostring(r.value or 0) end
  local numCell = cell(fcol, { left = 0, right = 0, top = 0, bottom = 0 }, numTxt, "Regular14", "Right", dimc())
  local track = fcol:Append("UIObject"); track.Anchors = { left = 0, right = 0, top = 1, bottom = 1 }
  pcall(function() track.H = "7" end); applyBg(track, "faderTrack")
  local fill
  if r.state ~= "missing" then
    fill = track:Append("UIObject")
    pcall(function() fill.W = tostring(r.value or 0) .. "%"; fill.H = "100%" end)
    applyBg(fill, r.state == "parked" and "textDim" or "faderFill")   -- cyan assigned / dim parked
  end
  -- the CheckBox tick (col 3) — this IS the assignment. State 0/1 + Clicked signal.
  local cb = grid:Append("CheckBox"); cb.Anchors = { left = 3, right = 3, top = top, bottom = top }
  pcall(function() cb.State = (r.ticked and 1 or 0) end)
  cb.Name = "ObjTick_" .. tostring(r.key)
  local gated = (M._selected ~= nil) and (M._selectedType ~= nil)
  if gated then cb.PluginComponent = my_handle; cb.Clicked = "Obj_Tick"
  else pcall(function() cb.Enabled = "No" end) end
  if r.ticked then paintTick(cb, true) end
  -- retain handles for a per-tick in-place recolor (Assign-all re-reads the pool fresh)
  M._objRows[r.key] = { fill = fill, checkbox = cb, numeric = numCell, backplate = bp, state = r.state }
end

-- M.refreshObjects — rebuild ONLY the pane-3 body (a row-SET change: type select, browse,
-- bulk assign). A single tick NEVER routes here (it recolors one row in place). Empty/guard
-- states render a dim centered message; ticks/bulk stay disabled until snapshot AND type.
function M.refreshObjects()
  local box = M._ui and M._ui.objBox
  if not box then return end
  pcall(function() box:ClearUIChildren() end)
  M._objRows, M._objRefs = {}, {}

  local function emptyMsg(txt)
    local grid = box:Append("UILayoutGrid"); grid.ContentDriven = true
    grid.Columns, grid.Rows = 1, 1
    cell(grid, { left = 0, right = 0, top = 0, bottom = 0 }, txt, "Regular14", "Center", dimc())
    pcall(function() box:WaitInit(2) end); pcall(function() grid:WaitInit(2) end)
  end

  if M._selected == nil then
    emptyMsg("Select a snapshot to assign objects."); setObjActionState(); return
  end
  if M._selectedType == nil then
    emptyMsg("Select a type to see its objects."); setObjActionState(); return
  end

  -- refresh the datapool-selector strip: a live dropdown for pool types, hidden otherwise
  pcall(function()
    if M._ui.dpSel then
      local lbl, en = dpLabel()
      M._ui.dpSel.Text = lbl
      M._ui.dpSel.Visible = en and "Yes" or "No"
      M._ui.dpSel.Enabled = en and "Yes" or "No"
    end
  end)

  -- reads (both pcall-wrapped): the live pool for the selected type + the selected snapshot.
  -- Pool types (sequence/preset/group) honour the datapool selector; executor/master ignore it.
  local pool_objs = {}
  pcall(function()
    if isPoolType(M._selectedType) then
      pool_objs = Snapshots.ma3.pool_objects(M._selectedType, M._datapool) or {}
    else
      pool_objs = Snapshots.ma3.pool_objects(M._selectedType) or {}
    end
  end)
  local snap = currentSnap()
  local rows = {}
  -- when a datapool is picked, don't append other-datapool members as "Missing"
  pcall(function() rows = Snapshots.assign.object_rows(pool_objs, snap, M._selectedType, M._datapool ~= nil) or {} end)

  -- Topbar live-search (pane 3): narrow the row set to label/addr substring matches. CONTENT-only
  -- — the topbar itself is never rebuilt. Pure Snapshots.search call, pcall-guarded.
  if M._query and M._query ~= "" then
    pcall(function() rows = Snapshots.search.filter_rows(M._query, rows) or rows end)
  end

  -- retain the REAL refs (pool objects first, then any off-pool member refs) so the tick
  -- handler can pass a proper schema ref to Snapshots.assign.*
  for _, obj in ipairs(pool_objs) do
    local ok, k = pcall(function() return Snapshots.schema.key(obj) end)
    if ok and k then M._objRefs[k] = obj end
  end
  for _, m in ipairs((snap and snap.members) or {}) do
    local ok, k = pcall(function() return Snapshots.schema.key(m.ref) end)
    if ok and k and not M._objRefs[k] then M._objRefs[k] = m.ref end
  end

  if #rows == 0 then
    emptyMsg("No assignable objects in this pool."); setObjActionState(); return
  end

  -- paginate the row set for browse (ASGN-04)
  local total = #rows
  local pages = math.max(1, math.ceil(total / OBJ_PAGE_SIZE))
  M._objCursor = M._objCursor or { page = 1 }
  local page = M._objCursor.page or 1
  if page > pages then page = pages end
  if page < 1 then page = 1 end
  M._objCursor.page, M._objCursor.pages = page, pages
  local first = (page - 1) * OBJ_PAGE_SIZE + 1
  local last  = math.min(total, page * OBJ_PAGE_SIZE)

  pcall(function() if M._ui.objPageLabel then M._ui.objPageLabel.Text = "pg " .. page .. " / " .. pages end end)
  pcall(function() if M._ui.objPrev then M._ui.objPrev.Enabled = (page > 1) and "Yes" or "No" end end)
  pcall(function() if M._ui.objNext then M._ui.objNext.Enabled = (page < pages) and "Yes" or "No" end end)

  local count = last - first + 1
  local grid = box:Append("UILayoutGrid"); grid.ContentDriven = true
  grid.Columns, grid.Rows = 5, math.max(count, 1)
  -- col 4 is a trailing spacer so the CheckBox (col 3) is NOT flush against the scrollbar edge
  -- (it was clipped/partially hidden onPC). tag | label | fader | tick | gap.
  setCols(grid, { { w = 34 }, {}, { w = 74 }, { w = 34 }, { w = 18 } })

  local idx = 0
  for ri = first, last do
    idx = idx + 1
    -- per-row colour by the object's REAL type (so the Executor masters pane is MIXED-colour —
    -- a fader is just a locator; each object keeps its own type/colour). Falls back to the pane.
    buildObjRow(grid, idx, rows[ri], catSwatch(rows[ri].type or M._selectedType))
  end

  M._ui.objGrid = grid
  pcall(function() box:WaitInit(2) end); pcall(function() grid:WaitInit(2) end)
  setObjActionState()
end

-- M.refreshTypeFilter — dim the pane-2 categories whose live pool has ZERO objects matching the
-- current search query (empty query ⇒ restore all to normal). Reuses the cached pool refs
-- (M._poolRefs — no new pool walk) + the retained pane-2 button handles for an IN-PLACE text
-- recolor; NEVER rebuilds pane 2, so the EXEC/DATAPOOL/GLOBALS dividers stay put. Per-category
-- match counts come from the pure Snapshots.search.category_counts helper.
function M.refreshTypeFilter()
  local q = M._query
  local active = (q ~= nil and q ~= "")
  -- one label/addr/category row per cached pool object (the pane-3 haystack, per category)
  local rows = {}
  pcall(function()
    for cat, objs in pairs(M._poolRefs or {}) do
      for _, obj in ipairs(objs) do
        rows[#rows + 1] = { label = obj.label, addr = obj.addr, category = cat }
      end
    end
  end)
  local counts = {}
  pcall(function() counts = Snapshots.search.category_counts(q, rows) or {} end)
  for cat, bp in pairs(M._typeRowBtns or {}) do
    local dim = active and ((counts[cat] or 0) == 0)
    pcall(function() bp.TextColor = dim and dimc() or TXT.bright end)
  end
end

-- buildPane3 — the LIVE Object pane: header (browse nav) + ContentDriven scroll body +
-- bulk-assign footer. The body is filled by M.refreshObjects (called here and on every
-- set change). ASGN-03 "Assign selection" is DEFERRED — no selection read is fabricated.
local function buildPane3(host, deps)
  local fr = paneFrame(host, 3)
  -- rows: header(26) · datapool-selector strip(30) · scroll body(stretch) · footer(40)
  local wrap = fr:Append("UILayoutGrid"); wrap.Anchors = "0,0"; wrap.Columns, wrap.Rows = 1, 4
  rowH(wrap, 1, 26); rowH(wrap, 2, 30); pcall(function() wrap[1][3].SizePolicy = "Stretch" end); rowH(wrap, 4, 40)

  -- header (row 1): "OBJECT" + browse nav (‹ / DP·pg / ›)
  local hdr = wrap:Append("UILayoutGrid"); hdr.Anchors = { left = 0, right = 0, top = 0, bottom = 0 }
  hdr.Columns, hdr.Rows = 4, 1; setCols(hdr, { {}, { w = 34 }, { w = 96 }, { w = 34 } })
  cell(hdr, { left = 0, right = 0, top = 0, bottom = 0 }, "OBJECT", "Regular14", "Left", dimc())
  -- Text arrows, NOT Icon="left"/"right" — those aren't valid MA3 icon resources and spam the
  -- System Monitor with "Could not resolve object address for left/right" (onPC-verified).
  local prev = iconBtn(hdr, { left = 1, right = 1, top = 0, bottom = 0 }, nil, "‹", "Obj_BrowsePrev")
  local pageLbl = cell(hdr, { left = 2, right = 2, top = 0, bottom = 0 }, "pg 1 / 1", "Regular14", "Center", dimc())
  local nxt = iconBtn(hdr, { left = 3, right = 3, top = 0, bottom = 0 }, nil, "›", "Obj_BrowseNext")

  -- datapool selector strip (row 2): a FIXED full-width dropdown button, ABOVE the scroll body so
  -- clicking it never clears itself (a button inside the ScrollBox self-deletes on refresh → the
  -- list went blank onPC). Text/enabled are updated per-type in refreshObjects.
  local dpSel = iconBtn(wrap, { left = 0, right = 0, top = 1, bottom = 1 }, nil, "▾ All datapools", "Obj_PickDatapool", { align = "Left" })
  applyBg(dpSel, "hover"); M._ui.dpSel = dpSel

  -- body (row 3): the verified ContentDriven scroll stack
  local sc = wrap:Append("ScrollContainer"); sc.Anchors = { left = 0, right = 0, top = 2, bottom = 2 }
  local box = sc:Append("ScrollBox"); box.ContentDriven = true; box.Margin = "0,0,20,0"

  -- footer (row 4): the bulk-assign action bar — Assign none · Assign all
  local ft = wrap:Append("UILayoutGrid"); ft.Anchors = { left = 0, right = 0, top = 3, bottom = 3 }
  ft.Columns, ft.Rows = 2, 1; setCols(ft, { {}, {} })
  local noneBtn = iconBtn(ft, { left = 0, right = 0, top = 0, bottom = 0 }, nil, "Assign none", "Obj_AssignNone")
  local allBtn  = iconBtn(ft, { left = 1, right = 1, top = 0, bottom = 0 }, nil, "Assign all", "Obj_AssignAll")

  M._ui.objBox       = box
  M._ui.objPageLabel = pageLbl
  M._ui.objPrev, M._ui.objNext = prev, nxt
  M._ui.assignNoneBtn, M._ui.assignAllBtn = noneBtn, allBtn

  M.refreshObjects()
end

-- ── buildPane1 — the LIVE Snapshot pane: header + scroll list + footer ────────
local function buildPane1(host, deps)
  local fr = paneFrame(host, 1)
  -- rows: header(26) · scroll list(stretch) · toolbar row 1(40) · toolbar row 2(40)
  local wrap = fr:Append("UILayoutGrid"); wrap.Anchors = "0,0"; wrap.Columns, wrap.Rows = 1, 4
  rowH(wrap, 1, 26); pcall(function() wrap[1][2].SizePolicy = "Stretch" end); rowH(wrap, 3, 40); rowH(wrap, 4, 40)

  -- header (row 1): "SNAPSHOT" title only — all actions live in the bottom toolbar now
  local hdr = wrap:Append("UILayoutGrid"); hdr.Anchors = { left = 0, right = 0, top = 0, bottom = 0 }
  hdr.Columns, hdr.Rows = 1, 1
  cell(hdr, { left = 0, right = 0, top = 0, bottom = 0 }, "SNAPSHOT", "Regular14", "Left", dimc())

  -- body (row 2): the verified ContentDriven scroll stack
  local sc = wrap:Append("ScrollContainer"); sc.Anchors = { left = 0, right = 0, top = 1, bottom = 1 }
  local box = sc:Append("ScrollBox"); box.ContentDriven = true; box.Margin = "0,0,20,0"

  -- toolbar row 1 (row 3): New · Rename… — New is always enabled; Rename is selection-gated
  local tb1 = wrap:Append("UILayoutGrid"); tb1.Anchors = { left = 0, right = 0, top = 2, bottom = 2 }
  tb1.Columns, tb1.Rows = 2, 1; setCols(tb1, { {}, {} })
  iconBtn(tb1, { left = 0, right = 0, top = 0, bottom = 0 }, "plus", "New", "Snap_New")
  local renameBtn = iconBtn(tb1, { left = 1, right = 1, top = 0, bottom = 0 }, nil, "Rename…", "Snap_Rename")

  -- toolbar row 2 (row 4): Duplicate · Clear… · Delete… (red) — all selection-gated
  local tb2 = wrap:Append("UILayoutGrid"); tb2.Anchors = { left = 0, right = 0, top = 3, bottom = 3 }
  tb2.Columns, tb2.Rows = 3, 1; setCols(tb2, { {}, {}, {} })
  local dupBtn   = iconBtn(tb2, { left = 0, right = 0, top = 0, bottom = 0 }, nil, "Duplicate", "Snap_Duplicate")
  local clearBtn = iconBtn(tb2, { left = 1, right = 1, top = 0, bottom = 0 }, nil, "Clear…", "Snap_Clear")
  local deleteBtn = iconBtn(tb2, { left = 2, right = 2, top = 0, bottom = 0 }, nil, "Delete…", "Snap_Delete",
    { text = themeRef("red") })
  pcall(function() renameBtn.Enabled = "No"; dupBtn.Enabled = "No"; clearBtn.Enabled = "No"; deleteBtn.Enabled = "No" end)

  M._ui.listBox = box
  M._ui.dupBtn, M._ui.renameBtn, M._ui.clearBtn, M._ui.deleteBtn = dupBtn, renameBtn, clearBtn, deleteBtn
  renderList(deps)
end

-- ══ PHASE-9 playback bar (UI-02) + Fade/Snap toggle (RCL-04) ═══════════════════
-- A playback-ONLY bottom action bar. Every button is a THIN caller of the already-
-- tested engine — it synthesizes an arg via Snapshots.args.build and calls
-- Snapshots.dispatch.execute (the SAME pipeline as the macro surface), or calls
-- Snapshots.manager.set_default_fade. ZERO recall/store/persistence logic lives here.
-- NO New/Clear/Delete in this bar (they stay in the pane-1 header/footer — a
-- destructive action is never a mis-tap from Recall).

-- Format fade seconds like the args layer (fmt_fade %g): 3.0→"3", 2.5→"2.5", 0→"0".
local function fmtFade(n) return string.format("%g", tonumber(n) or 0) end

-- updateFadeValueBtn — relabel + recolor the Fade-value Button IN PLACE per mode.
-- Fade mode: "Fade <n>s" (cyan numeric intent). Snap mode: dims to textDim, reads "Snap".
local function updateFadeValueBtn()
  local b = M._ui and M._ui.fadeValBtn
  if not b then return end
  pcall(function()
    if M._snapMode then
      b.Text = "Snap"; b.TextColor = dimc()
    else
      b.Text = "Fade " .. fmtFade(M._fadeSeconds) .. "s"
      b.TextColor = themeRef("cyan") or TXT.bright
    end
  end)
end

-- paintToggle — recolor + relabel the Fade/Snap IndicatorButton IN PLACE. Sets BOTH
-- BackColor AND ActiveBackColor (the colored-checked caveat): Fade=cyan/"Fade"/State 1,
-- Snap=amber/"Snap"/State 0. Off-desk (nil ref) leaves the widget default.
local function paintToggle()
  local t = M._ui and M._ui.snapToggle
  if not t then return end
  pcall(function()
    if M._snapMode then
      t.State = 0; t.Text = "Snap"
      local r = themeRef("amber"); if r then t.BackColor = r; t.ActiveBackColor = r end
    else
      t.State = 1; t.Text = "Fade"
      local r = themeRef("cyan"); if r then t.BackColor = r; t.ActiveBackColor = r end
    end
  end)
end

-- vdiv — a thin 1px VERTICAL group divider for the playback bar. A nested 3-col grid
-- ( {}, { w = 1 }, {} ) with a non-interactive UIObject line anchored to the centre column,
-- painted with the theme's textDim swatch (same line styling as buildTypeDivider).
local function vdiv(bar, col)
  pcall(function()
    local sub = bar:Append("UILayoutGrid"); sub.Anchors = { left = col, right = col, top = 0, bottom = 0 }
    sub.Columns, sub.Rows = 3, 1
    setCols(sub, { {}, { w = 1 }, {} })
    local line = sub:Append("UIObject"); line.Anchors = { left = 1, right = 1, top = 0, bottom = 0 }
    pcall(function() line.HasHover = "No"; line.Focus = "Never" end)
    applyBg(line, "textDim")
  end)
end

-- buildPlaybackBar — one single-row UILayoutGrid mounted at root[1][3] (Anchors "0,2").
-- Columns (left→right): [Recall · Breakdown] | vdiv | [Store] · stretch · vdiv | [Fade-value ·
-- Default-fade · Fade/Snap toggle]. Three playback-only groups split by two 1px vertical
-- dividers. All appends are verified classes (Button + IndicatorButton), every reach
-- pcall-guarded. Handles cached in M._ui for enable-state + in-place relabel.
local function buildPlaybackBar(root, deps)
  local fr = barFrame(root, 4)   -- outlined pane-style card (frame15) — carries the surface fill (row 4)
  local bar
  pcall(function()
    bar = fr:Append("UILayoutGrid"); bar.Anchors = "0,0"; bar.H, bar.W = "100%", "100%"
    bar.Columns, bar.Rows = 9, 1
    pcall(function() bar.Margin = "10,6,10,6" end)
  end)
  if not bar then return end
  -- Group 1 [Recall · Breakdown] | vdiv | Group 2 [Store] · stretch · vdiv | Group 3
  -- [Fade-value · Default-fade · Fade/Snap toggle]. Col 4 is the Stretch spacer.
  setCols(bar, { { w = 120 }, { w = 140 }, { w = 15 }, { w = 110 }, {}, { w = 15 }, { w = 150 }, { w = 150 }, { w = 140 } })

  -- Group 1 (left): playback — Recall + Breakdown, adjacent
  M._ui.recallBtn    = iconBtn(bar, { left = 0, right = 0, top = 0, bottom = 0 }, nil, "Recall", "Play_Recall", { text = themeRef("cyan") })
  M._ui.breakdownBtn = iconBtn(bar, { left = 1, right = 1, top = 0, bottom = 0 }, nil, "Breakdown", "Play_Breakdown", { text = themeRef("amber") })

  vdiv(bar, 2)   -- divider 1: playback | store

  -- Group 2 (middle): Store, alone
  M._ui.storeBtn     = iconBtn(bar, { left = 3, right = 3, top = 0, bottom = 0 }, nil, "Store", "Play_Store")
  -- col 4 is the Stretch spacer (no widget) — pushes the settings cluster to the right edge

  vdiv(bar, 5)   -- divider 2: store | settings

  -- Group 3 (right): fade settings — Fade-value · Default-fade · Fade/Snap toggle
  M._ui.fadeValBtn   = iconBtn(bar, { left = 6, right = 6, top = 0, bottom = 0 }, nil, "Fade 3s", "Play_FadeValue")   -- global; always enabled
  M._ui.defFadeBtn   = iconBtn(bar, { left = 7, right = 7, top = 0, bottom = 0 }, nil, "Default fade", "Play_DefaultFade")

  local toggle
  pcall(function()
    toggle = bar:Append("IndicatorButton"); toggle.Anchors = { left = 8, right = 8, top = 0, bottom = 0 }
    toggle.Text = "Fade"; toggle.Font = "Regular16"
    pcall(function() toggle.State = 1 end)
    toggle.PluginComponent = my_handle; toggle.Clicked = "Play_FadeSnap"   -- global; always enabled
  end)
  M._ui.snapToggle = toggle

  paintToggle()          -- initial lamp/label (cyan/"Fade"/State 1)
  updateFadeValueBtn()   -- initial "Fade 3s"
end

-- ══ PHASE-9 System Monitor strip (UI-03) ══════════════════════════════════════
-- A fixed UILayoutGrid (Columns=1, Rows=N) of UIObject line-cells at root[1][4], mirroring
-- the recent Snapshots.monitor.list() notify lines — the SAME messages that reach the real
-- MA3 System Monitor. Newest at the BOTTOM. The warn classifier (skip/missing/error/…) is a
-- RENDER concern only, so lib/monitor.lua stays a plain string ring buffer.

-- isWarnLine — case-insensitive substring match on the warn/skip tokens (UI-SPEC). A plain
-- find(...,true) substring test — never load()/eval of the notify string (T-09-16).
local WARN_TOKENS = { "skip", "missing", "no guid", "error", "invalid", "unknown", "deferred" }
local function isWarnLine(s)
  local low = tostring(s):lower()
  for _, p in ipairs(WARN_TOKENS) do
    if low:find(p, 1, true) then return true end
  end
  return false
end

-- buildMonitorStrip — mount the strip at root[1][4] (Anchors "0,3") as a ScrollBox host. The
-- lines are drawn by refreshMonitor into a CONTENT-DRIVEN inner grid (one row per real message,
-- ZERO rows when empty). The old design pre-baked MON_LINES empty grid rows, and MA3 renders an
-- empty UILayoutGrid's rows as faint separator bands — the "weird horizontal lines" reported onPC.
local function buildMonitorStrip(root, deps)
  local fr = barFrame(root, 5)   -- outlined pane-style card (frame15) — carries the surface fill (row 5)
  local strip
  pcall(function()
    strip = fr:Append("UILayoutGrid"); strip.Anchors = "0,0"; strip.H, strip.W = "100%", "100%"
    strip.Columns, strip.Rows = 1, 1
    pcall(function() strip.Margin = "10,4,10,4" end)
  end)
  if not strip then return end
  -- ONE status line, updated IN PLACE (never appended). A status bar, NOT a growing log — the
  -- content-driven list rendered every ring-buffer entry and overflowed the window bottom (onPC).
  M._ui.monLine = cell(strip, { left = 0, right = 0, top = 0, bottom = 0 }, "", "Regular14", "Left", dimc())
end

-- ── buildTopbar — the live-search + About row between the titlebar and the body ─
-- One outlined barFrame card (matches the panes / bottom bars) holding a single-row grid:
-- a decorative "Search" label (left, plain cell — no icon, to avoid the System Monitor
-- "could not resolve icon" spam the manager hit with Icon="left"/"right"), the search LineEdit
-- (stretch middle; value = .Content, change signal TextChanged=Snap_Search), and an About icon
-- Button (right). Built ONCE at chrome mount; Snap_Search repaints CONTENT only and NEVER
-- rebuilds this row (so the caret/focus survive every keystroke).
local function buildTopbar(root, deps)
  local fr = barFrame(root, 2)   -- row-2 card (Anchors "0,1")
  local bar
  pcall(function()
    bar = fr:Append("UILayoutGrid"); bar.Anchors = "0,0"; bar.H, bar.W = "100%", "100%"
    bar.Columns, bar.Rows = 3, 1
    pcall(function() bar.Margin = "10,4,10,4" end)
  end)
  if not bar then return end
  setCols(bar, { { w = 80 }, {}, { w = 50 } })
  -- NO rowH here: the single row inherits bar.H="100%" and stretches to the frame's inner height
  -- (~50px at an 84px topbar row). An explicit rowH fought bar.H and collapsed the grid to 28px,
  -- clipping the field + About icon. Let it fill instead.

  cell(bar, { left = 0, right = 0, top = 0, bottom = 0 }, "Search", "Regular18", "Left", dimc())

  local le
  pcall(function()
    le = bar:Append("LineEdit"); le.Anchors = { left = 1, right = 1, top = 0, bottom = 0 }
    le.Content = ""
    -- LineEdit defaults to ContentHeight=Yes → collapses to font height (~8px). Force it to FILL
    -- the row so it's a real touch target.
    pcall(function() le.ContentHeight = "No"; le.H = "100%" end)
    le.Font = "Regular24"
    le.PluginComponent = my_handle; le.TextChanged = "Snap_Search"
    le.Focus = "InitialFocus"
  end)
  applyBg(le, "row")
  M._ui.searchEdit = le

  iconBtn(bar, { left = 2, right = 2, top = 0, bottom = 0 }, "object_info", nil, "OnAbout")
end

-- ── buildChrome — mount the ScreenOverlay → BaseInput root + skeleton + 3 panes ─
-- Standard mount recipe: GetFocusDisplay().ScreenOverlay → ClearUIChildren →
-- theme.install() → Append("BaseInput") with CanCoexistWithModal="Yes" (native Confirm/
-- MessageBox must NOT tear the manager down). Skeleton: root[1][1] Fixed 55 (title),
-- root[1][2] Stretch (body). Body = a 3-col UILayoutGrid of DialogFrame panes at 1fr/1fr/1fr.
local function buildChrome(deps)
  local display
  local okd = pcall(function() display = GetFocusDisplay() end)
  if not okd or not display then return end
  pcall(function() if Obj.Index(display) > 5 then display = GetDisplayByIndex(1) end end)

  local overlay
  pcall(function() overlay = display.ScreenOverlay end)
  if not overlay then return end
  pcall(function() overlay:ClearUIChildren() end)          -- the ONE mount-time clear
  pcall(function() Snapshots.ui.theme.install() end)        -- idempotent swatch registry

  local root
  pcall(function()
    root = overlay:Append("BaseInput"); root.Name = "SnapshotsManager"
    root.W, root.H = 1400, 880; root.AlignmentH, root.AlignmentV = "Center", "Center"
    root.Columns, root.Rows = 1, 5   -- title · topbar · body · playback bar · monitor strip
    root.AutoClose, root.CloseOnEscape = "No", "Yes"; root.PluginComponent = my_handle
    root.CanCoexistWithModal = "Yes"   -- ◄ native Confirm/MessageBox won't tear us down (UI-SPEC)
    root.OverrideKeybSC = "Yes"        -- search keystrokes land in the field, NOT the command line
  end)
  if not root then return end
  applyBg(root, "bg")
  pcall(function() root[1][1].SizePolicy = "Fixed";   root[1][1].Size = "55" end)    -- title
  pcall(function() root[1][2].SizePolicy = "Fixed";   root[1][2].Size = "84" end)    -- topbar (search + About) — tall enough that frame15 chrome (~28px) still leaves a ~46px field
  pcall(function() root[1][3].SizePolicy = "Stretch" end)                            -- body (3 panes)
  pcall(function() root[1][4].SizePolicy = "Fixed";   root[1][4].Size = "120" end)   -- playback bar (touch height)
  pcall(function() root[1][5].SizePolicy = "Fixed";   root[1][5].Size = "75" end)    -- monitor strip
  titlebar(root, "Snapshots")
  buildTopbar(root, deps)   -- search + About row (built ONCE; search repaints content only)

  local body
  pcall(function()
    body = root:Append("UILayoutGrid"); body.Anchors = "0,2"; body.H, body.W = "100%", "100%"
    body.Columns, body.Rows = 3, 1
  end)
  if not body then return root end
  setCols(body, { {}, {}, {} })   -- even 1fr / 1fr / 1fr
  applyBg(body, "bg")

  buildPane1(body, deps)
  buildPane2(body, deps)
  buildPane3(body, deps)

  -- Append the playback-only action bar (row 4) + the System Monitor strip (row 5) AFTER the
  -- panes. The skeleton rows were sized upfront (title · topbar · body · bar · strip); each
  -- reach is pcall-guarded and both regions span full width (bar at "0,3", strip at "0,4").
  buildPlaybackBar(root, deps)
  buildMonitorStrip(root, deps)
  setActionState()   -- WR-01: apply the selection gate at init — no row selected yet, so the
                     -- playback bar's Recall/Store/Breakdown/Default-fade start DISABLED (mirrors
                     -- pane-1's build-time disable), instead of looking active until the first select.

  pcall(function() root:WaitInit(2) end)
  return root
end

-- ── M.open(deps) — the public entry dispatch.open_manager calls (deps.ui.open) ─
-- pcall-wrap the whole build so a widget-API drift surfaces as a logged notify, never a
-- torn overlay. Resets selection + retained handles for a clean re-open.
function M.open(deps)
  -- WR-01: teardown() is a hard obligation because the swatches mutate the show-saved
  -- Root().ColorTheme. The CloseButton→OnClose path can be bypassed by CloseOnEscape,
  -- leaking SnapshotsColors into the showfile. Defensively clear any residue from a prior
  -- Escape-close BEFORE buildChrome re-installs — teardown() is idempotent (find-or-clear).
  pcall(function() if Snapshots.ui and Snapshots.ui.theme then Snapshots.ui.theme.teardown() end end)
  M._deps = deps
  M._selected = nil
  M._ui = {}
  M._rowBtns, M._rowStripes, M._rowBadges = {}, {}, {}
  -- Phase-8 cross-pane state reset for a clean re-open
  M._selectedType = nil
  M._objCursor = { page = 1 }
  M._typeRowBtns, M._typeCountCells = {}, {}
  M._objRows, M._objRefs = {}, {}
  M._poolRefs = {}
  M._datapool = nil
  M._query = ""   -- clear the topbar search on every (re)open — a fresh field starts empty
  local ok, err = pcall(function() buildChrome(deps) end)
  if not ok then
    pcall(function() if deps and deps.notify then deps.notify("[ui.manager] open error: " .. tostring(err)) end end)
  end
  pcall(function() M.refreshMonitor() end)   -- initial paint of the System Monitor strip
end

-- ── M.refresh — rebuild ONLY the list body + re-derive action enabled-state ────
function M.refresh()
  local deps = M._deps
  if not deps then return end
  pcall(function() renderList(deps) end)
  setActionState()
end

-- ── M.refreshMonitor — rebuild the strip's line list from monitor.list() ───────
-- Reads Snapshots.monitor.list() at CALL time (pcall-guarded; nil → {}) and rebuilds a
-- CONTENT-DRIVEN inner grid — one row per message (oldest→newest, newest at the BOTTOM),
-- each colored warn/skip → amber else bright. EMPTY buffer → the box holds nothing (no
-- placeholder, no banding). Called from M.open + every notify-producing handler.
function M.refreshMonitor()
  local ln = M._ui and M._ui.monLine
  if not ln then return end
  local list = {}
  pcall(function() list = (Snapshots.monitor and Snapshots.monitor.list()) or {} end)
  local msg = list[#list]   -- newest message only — overwrite the ONE line in place, no growth
  pcall(function()
    if msg and msg ~= "" then
      ln.Text = tostring(msg)
      ln.TextColor = isWarnLine(msg) and (themeRef("amber") or TXT.bright) or TXT.bright
    else
      ln.Text = ""
    end
  end)
end

-- ── signalTable handlers — THIN adapters: read widget → Snapshots.manager.* → repaint ─
-- Snapshots.manager is resolved at CALL time. Every prompt uses the native blocking helpers
-- (MessageBox / TextInput / Confirm) — the only verified modal path. NO lifecycle logic here.

signalTable.Snap_New = function()
  local deps = M._deps; if not deps then return end
  -- TextInput (virtual keyboard) rather than MessageBox: the MessageBox command buttons don't
  -- accept a MOUSE click when the manager overlay coexists with the modal (onPC) — only Enter
  -- worked. TextInput (same as Rename) is confirmed working. Returns the name, or nil on cancel.
  local name
  pcall(function() name = TextInput("Name", "") end)
  if name and tostring(name):match("%S") then
    pcall(function() Snapshots.manager.create(deps, name) end)
    M.refresh()
  end
end

signalTable.Snap_Rename = function()
  local deps = M._deps; if not deps or not M._selected then return end
  local cur = nameOf(M._selected)
  local newName
  pcall(function() newName = TextInput("Name", cur) end)   -- title bar force-prefixes "Edit"
  if newName and tostring(newName):match("%S") then
    pcall(function() Snapshots.manager.rename(deps, M._selected, newName) end)
    M.refresh()
  end
end

signalTable.Snap_Duplicate = function()
  local deps = M._deps; if not deps or not M._selected then return end
  local newid
  pcall(function() newid = Snapshots.manager.duplicate(deps, M._selected) end)
  if newid then M._selected = tostring(newid) end   -- select the new copy
  M.refresh()
end

signalTable.Snap_Clear = function()
  local deps = M._deps; if not deps or not M._selected then return end
  local nm = nameOf(M._selected)
  local ok = false
  pcall(function() ok = Confirm("Clear snapshot?", "Empties stored values and assignments. '" .. nm .. "' stays.", nil, true) end)
  if ok then
    pcall(function() Snapshots.manager.clear(deps, M._selected) end)
    M.refresh()
  end
end

signalTable.Snap_Delete = function()
  local deps = M._deps; if not deps or not M._selected then return end
  local nm = nameOf(M._selected)
  local ok = false
  pcall(function() ok = Confirm("Delete snapshot?", "Removes '" .. nm .. "' and all its data. Cannot be undone.", nil, true) end)
  if ok then
    pcall(function() Snapshots.manager.delete(deps, M._selected) end)
    M._selected = nil
    M.refresh()
  end
end

-- Topbar live search: read the LineEdit .Content, store the lowercased query, repaint CONTENT
-- only (pane 3 row filter + pane 2 category dim) and re-assert focus so typing stays in the
-- field. The topbar itself is NEVER rebuilt — caret/focus survive every keystroke.
signalTable.Snap_Search = function(caller)
  local q = ""
  pcall(function() q = caller and caller.Content or "" end)
  M._query = tostring(q):lower()
  pcall(function() M.refreshObjects() end)      -- pane 3: filter rows
  pcall(function() M.refreshTypeFilter() end)   -- pane 2: dim zero-match categories
  pcall(function() if M._ui.searchEdit then M._ui.searchEdit.Focus = "WantsFocus" end end)
end

-- About button → the scoped About window (call-time lookup — siblings are not require-able).
signalTable.OnAbout = function() pcall(function() Snapshots.ui.about.open() end) end

-- Row select: recolor old + new row IN PLACE (never rebuild), recover id via .Name regex.
signalTable.Snap_Select = function(caller)
  local id = tostring(caller and caller.Name or ""):match("SnapRow_(.+)")
  if not id then return end
  if M._selected and M._rowBtns[M._selected] then
    styleRow(M._rowBtns[M._selected], M._rowStripes[M._selected], false)
  end
  styleRow(M._rowBtns[id], M._rowStripes[id], true)
  M._selected = id
  setActionState()
  -- seed the next-recall fade override from the selected snapshot's stored default
  -- (fallback 3.0), then relabel the Fade-value button in place (RCL-03 default carry).
  M._fadeSeconds = 3.0
  pcall(function()
    local snap = currentSnap()
    if snap and type(snap.fade) == "number" then M._fadeSeconds = snap.fade end
  end)
  pcall(function() updateFadeValueBtn() end)
  -- the assignment target changed → re-derive panes 2/3 for THIS snapshot's membership
  -- (a set change for pane 3; an in-place count update for pane 2).
  M._objCursor = { page = 1 }
  pcall(function() refreshTypeCounts() end)
  pcall(function() M.refreshObjects() end)
  pcall(function() coroutine.yield(0) end)   -- yield to repaint (no window flash)
end

-- ══ PHASE-8 handlers — Type select · Object tick (assign/park) · browse · bulk assign ══

-- Type select: recover the category via .Name regex, recolor old/new pane-2 rows IN PLACE,
-- set the selected type, reset the browse cursor, then rebuild pane-3 body (a set change).
signalTable.Type_Select = function(caller)
  local cat = tostring(caller and caller.Name or ""):match("TypeRow_(.+)")
  if not cat then return end
  if M._selectedType and M._typeRowBtns[M._selectedType] then
    styleRow(M._typeRowBtns[M._selectedType], nil, false)
  end
  if M._typeRowBtns[cat] then styleRow(M._typeRowBtns[cat], nil, true) end
  M._selectedType = cat
  -- default the datapool selector to the operator's CURRENT datapool (not "All") for pool types
  M._datapool = nil
  pcall(function() if isPoolType(cat) then M._datapool = Snapshots.ma3.current_datapool_index() end end)
  M._objCursor = { page = 1 }
  pcall(function() M.refreshObjects() end)
  pcall(function() coroutine.yield(0) end)
end

-- Object tick/untick — THE assignment (ASGN-01/02). Recover row key via .Name regex, read
-- caller.State, call the PURE Snapshots.assign.assign / .park (mutates the snap), persist via
-- the injected peer-safe deps.store.save (NEVER a whole-blob write), then recolor ONLY this
-- row in place + bump the pane-2 count — no body rebuild, no flash.
signalTable.Obj_Tick = function(caller)
  local key = tostring(caller and caller.Name or ""):match("ObjTick_(.+)")
  if not key then return end
  local deps = M._deps; if not deps or not M._selected then return end
  local ref = M._objRefs and M._objRefs[key]; if not ref then return end
  local snap = currentSnap(); if not snap then return end
  -- MA3 CheckBox does NOT auto-toggle: reading caller.State returns the
  -- state the box was BUILT with, unchanged by the click. We must flip it ourselves and act on
  -- the NEW state — otherwise clicking an unticked box reads 0 → park (no-op) → nothing assigns.
  local cur = 0; pcall(function() cur = caller.State or 0 end)
  local newv = (cur == 1) and 0 or 1
  pcall(function() caller.State = newv end)
  local newState
  if newv == 1 then
    -- capture the object's CURRENT live value so ticking a NEW object stores its value (not a
    -- placeholder 0); a re-tick of a parked member keeps its stored value (handled in assign).
    local captured = {}
    pcall(function() captured = Snapshots.ma3.capture({ ref }) or {} end)
    local val = captured[1] and captured[1].value
    pcall(function() Snapshots.assign.assign(snap, ref, val) end); newState = "assigned"
  else
    pcall(function() Snapshots.assign.park(snap, ref) end); newState = "parked"
  end
  pcall(function() deps.store.save(M._selected, snap) end)   -- peer-safe delta (Phase-4)
  -- in-place recolor of THIS row (value is kept by assign/park)
  local h = M._objRows and M._objRows[key]
  if h then
    local val = memberValue(snap, key)
    if h.fill then
      pcall(function() h.fill.W = tostring(val) .. "%" end)
      applyBg(h.fill, newState == "parked" and "textDim" or "faderFill")
    end
    if h.numeric then
      pcall(function() h.numeric.Text = (newState == "parked") and (tostring(val) .. " parked") or tostring(val) end)
    end
    paintTick(h.checkbox, newState == "assigned")
    h.state = newState
  end
  pcall(function() refreshTypeCounts() end)
  pcall(function() updateSnapBadge() end)    -- keep pane-1 assigned/stored badge in sync
  pcall(function() coroutine.yield(0) end)   -- yield to repaint (no body rebuild)
end

-- Browse prev/next — move the pane-3 page cursor and rebuild the body only (ASGN-04).
-- Datapool selector — a native PopupInput dropdown listing "All datapools" + each datapool.
-- PopupInput blocks until the operator picks; it returns a 0-based index and/or the value string
-- (community-documented), so resolve BOTH shapes defensively and ignore an unrecognised return.
signalTable.Obj_PickDatapool = function()
  if not isPoolType(M._selectedType) then return end
  local dps = {}
  pcall(function() dps = Snapshots.ma3.datapools() or {} end)
  local items = { "All datapools" }
  for _, d in ipairs(dps) do items[#items + 1] = tostring(d.name) end
  local sel, selval
  pcall(function() sel, selval = PopupInput({ title = "Datapool", caller = GetDisplayByIndex(1), items = items }) end)
  -- Resolve the pick to a 1-based position in `items`. Prefer a returned value STRING (unambiguous);
  -- otherwise the numeric return is a 1-based index onPC (NOT 0-based — a +1 picked the next
  -- datapool, e.g. picking Preview instead).
  local pick
  for _, v in ipairs({ selval, sel }) do
    if type(v) == "string" then
      for i, it in ipairs(items) do if it == v then pick = i end end
    end
  end
  if not pick and type(sel) == "number" then pick = sel end
  if pick == nil then return end                                       -- cancelled / unrecognised
  if pick <= 1 then M._datapool = nil                                  -- "All datapools"
  else M._datapool = dps[pick - 1] and dps[pick - 1].index or nil end
  M._objCursor = { page = 1 }
  pcall(function() M.refreshObjects() end)
end

signalTable.Obj_BrowsePrev = function()
  M._objCursor = M._objCursor or { page = 1 }
  if (M._objCursor.page or 1) > 1 then
    M._objCursor.page = M._objCursor.page - 1
    pcall(function() M.refreshObjects() end)
  end
end
signalTable.Obj_BrowseNext = function()
  M._objCursor = M._objCursor or { page = 1 }
  if (M._objCursor.page or 1) < (M._objCursor.pages or 1) then
    M._objCursor.page = M._objCursor.page + 1
    pcall(function() M.refreshObjects() end)
  end
end

-- Assign all (ASGN-04/06): assign every GUID-bearing object of the selected type (covers
-- browse-by-pool bulk and "assign all groups as groupmasters") via assign_many, save, rebuild.
signalTable.Obj_AssignAll = function()
  local deps = M._deps
  if not deps or not M._selected or not M._selectedType then return end
  local snap = currentSnap(); if not snap then return end
  local refs = {}
  pcall(function()
    if isPoolType(M._selectedType) then refs = Snapshots.ma3.pool_objects(M._selectedType, M._datapool) or {}
    else refs = Snapshots.ma3.pool_objects(M._selectedType) or {} end
  end)
  -- capture every object's live value once, so a bulk assign of NEW objects stores their values
  local vals = {}
  pcall(function()
    for _, cv in ipairs(Snapshots.ma3.capture(refs) or {}) do
      vals[Snapshots.schema.key(cv.ref)] = cv.value
    end
  end)
  for _, ref in ipairs(refs) do
    pcall(function() Snapshots.assign.assign(snap, ref, vals[Snapshots.schema.key(ref)]) end)
  end
  pcall(function() deps.store.save(M._selected, snap) end)
  pcall(function() M.refreshObjects() end)
  pcall(function() refreshTypeCounts() end)
  pcall(function() updateSnapBadge() end)
  pcall(function() M.refreshMonitor() end)   -- mirror the skip+notify lines (UI-03)
end

-- Assign none — the inverse of Assign all: park every object in THIS pane's pool only (NOT every
-- member across all types — M._objRefs also holds off-pool member refs from other panes). park is
-- a no-op on a non-member, so this only unassigns real members; values are kept for a later re-tick.
signalTable.Obj_AssignNone = function()
  local deps = M._deps
  if not deps or not M._selected or not M._selectedType then return end
  local snap = currentSnap(); if not snap then return end
  local refs = {}
  pcall(function()
    if isPoolType(M._selectedType) then refs = Snapshots.ma3.pool_objects(M._selectedType, M._datapool) or {}
    else refs = Snapshots.ma3.pool_objects(M._selectedType) or {} end
  end)
  for _, ref in ipairs(refs) do
    pcall(function() Snapshots.assign.park(snap, ref) end)
  end
  pcall(function() deps.store.save(M._selected, snap) end)
  pcall(function() M.refreshObjects() end)
  pcall(function() refreshTypeCounts() end)
  pcall(function() updateSnapBadge() end)
  pcall(function() M.refreshMonitor() end)
end

-- ══ PHASE-9 playback handlers — THIN callers of the tested engine (UI-02/RCL-04) ══
-- Recall/Store/Breakdown synthesize an arg via Snapshots.args.build and hand it to
-- Snapshots.dispatch.execute (the SAME pipeline as the macro surface), then repaint the
-- monitor strip. ZERO recall/store/persistence logic here — the args + dispatch layers
-- are already proven off-console. Cross-refs resolved at CALL time; every reach guarded.

-- playAction — shared body for the three engine buttons. verb ∈ {recall,store}; breakdown
-- appends the RCL-05 override (recall only). snap=M._snapMode ⇒ args.build emits fade=0.
local function playAction(verb, breakdown)
  local deps = M._deps; if not deps or not M._selected then return end
  local name = nameOf(M._selected)
  local arg  = Snapshots.args.build{ verb = verb, name = name,
                                     fade = M._fadeSeconds, snap = M._snapMode,
                                     breakdown = breakdown }
  pcall(function() Snapshots.dispatch.execute(arg, deps) end)   -- SAME tested pipeline
  if verb == "store" then
    -- Store captured fresh live fader values into the members → repaint the pane-3 level
    -- indicators (fader-bar + numeric) and the pane-1/2 counts, which read the updated store.
    pcall(function() M.refreshObjects() end)
    pcall(function() refreshTypeCounts() end)
    pcall(function() updateSnapBadge() end)
  end
  M.refreshMonitor()
end

signalTable.Play_Recall    = function() playAction("recall", false) end   -- RCL-01/02/03
signalTable.Play_Store     = function() playAction("store",  false) end   -- CAP-05
signalTable.Play_Breakdown = function() playAction("recall", true)  end   -- RCL-05

-- Play_FadeValue — MessageBox numeric prompt for the next-recall fade override. UI-only
-- state (no engine call): accept only a numeric >= 0, store to M._fadeSeconds, relabel in
-- place. Ignores non-numeric / negative input (keeps the prior value).
signalTable.Play_FadeValue = function()
  local s
  pcall(function() s = TextInput("Fade time (seconds)", tostring(M._fadeSeconds)) end)
  local n = tonumber(s)
  if n and n >= 0 then
    M._fadeSeconds = n
    updateFadeValueBtn()
  end
end

-- Play_DefaultFade — write the SELECTED snapshot's default fade (RCL-03) via the tested
-- manager op. MessageBox seeded from the snap's current default; on Set, a thin
-- Snapshots.manager.set_default_fade call (→ store.save) then refresh the strip.
signalTable.Play_DefaultFade = function()
  local deps = M._deps; if not deps or not M._selected then return end
  local cur = M._fadeSeconds
  pcall(function()
    local snap = currentSnap()
    if snap and type(snap.fade) == "number" then cur = snap.fade end
  end)
  local s
  pcall(function() s = TextInput("Default fade (seconds)", tostring(cur)) end)
  local n = tonumber(s)
  if n and n >= 0 then
    pcall(function() Snapshots.manager.set_default_fade(deps, M._selected, n) end)
    M.refreshMonitor()
  end
end

-- Play_FadeSnap — the global Fade/Snap toggle (RCL-04). Flip M._snapMode, recolor the
-- IndicatorButton + relabel the Fade-value button IN PLACE, yield to repaint. No engine
-- call — the mode drives the fade= value the arg surface already accepts.
signalTable.Play_FadeSnap = function()
  M._snapMode = not M._snapMode
  paintToggle()
  updateFadeValueBtn()
  pcall(function() coroutine.yield(0) end)
end

-- Close: parent-op teardown (child:Delete is a silent no-op) + MANDATORY theme teardown
-- (the SnapshotsColors swatches mutate the show-saved Root().ColorTheme — T-07-08).
signalTable.OnClose = function()
  pcall(function() GetFocusDisplay().ScreenOverlay:ClearUIChildren() end)
  pcall(function() Snapshots.ui.theme.teardown() end)
end

return M
