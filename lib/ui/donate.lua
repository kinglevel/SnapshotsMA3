-- lib/ui/donate.lua (Snapshots.ui.donate) — the donation QR overlay.
--
-- A themed, dismissible window showing a scannable QR of the donation URL, rendered natively as
-- a grid of black/white ColorTheme cells (the desk cannot draw an image), plus the URL as text.
-- Opened from the About window's ♥ Donate button. Public open()/close().
--
-- Sibling modules are NOT require-able, so the helpers are LIFTED here. The QR matrix comes from
-- the pure Snapshots.qrcode encoder (resolved at CALL time). A clipboard "Copy URL" button is
-- DROPPED (it would couple to a platform-specific clipboard seam); the URL is shown as copyable
-- text instead.
--
-- Colors: dark modules must be BLACK on WHITE for scannability, so this module owns TWO temp
-- ColorDefs (black/white) in a dedicated ColorGroup "SnapshotsQR", torn down on close (no
-- showfile pollution). UILayoutGrid does NOT paint BackColor, so the white card is a UIObject
-- backing under the module grid.
--
-- SCOPED-DISMISS: close() deletes ONLY this named BaseInput — NEVER a whole-overlay clear.
-- Global-namespace UI pattern. Varargs captured at FILE SCOPE. Every MA3 call pcall-wrapped.

Snapshots = Snapshots or {}
Snapshots.ui = Snapshots.ui or {}
local M = {}
Snapshots.ui.donate = M

local signalTable = select(3, ...)
local my_handle   = select(4, ...)

-- The donation destination — one swappable constant, encoded WITH the scheme so a phone scan
-- yields a tappable link. The copy text mirrors it exactly.
local DONATION_URL = "http://community.smidn.com/donate"

local NAME  = "SnapshotsDonate"   -- named overlay (scoped delete on dismiss)
local CT    = "SnapshotsQR"       -- temp ColorDef/Group name (torn down on close)
local QUIET = 4                   -- quiet-zone margin in modules

local C = { gold = "Global.Selected", soft = "Global.Bright" }

local function themeRef(role)
  local r; pcall(function() r = Snapshots.ui.theme and Snapshots.ui.theme.ref(role) end); return r
end

-- ── temp black/white ColorGroup refs ─────────────────────────────────────────
local function makeColor(name, hex)
  local ok, ref = pcall(function()
    local collect = Root().ColorTheme.ColorDefCollect
    local defGrp  = collect:Find(CT) or (function() local g = collect:Acquire(); g.Name = CT; return g end)()
    local cg      = Root().ColorTheme.ColorGroups
    local cgGrp   = cg:Find(CT) or (function() local g = cg:Acquire(); g.Name = CT; return g end)()
    local cd = defGrp:Acquire(); cd.Name = name; cd:Set("RGBA", hex)
    local r  = cgGrp:Acquire();  r.Name = name; r.ColorDefRef = cd
    return r
  end)
  return ok and ref or nil
end

local function cleanupColors()
  pcall(function()
    local cg = Root().ColorTheme.ColorGroups:Find(CT)
    if cg then Obj.Delete(Root().ColorTheme.ColorGroups, Obj.Index(cg)) end
    local cd = Root().ColorTheme.ColorDefCollect:Find(CT)
    if cd then Obj.Delete(Root().ColorTheme.ColorDefCollect, Obj.Index(cd)) end
  end)
end

local function currentOverlay()
  local o; pcall(function() o = GetFocusDisplay().ScreenOverlay end); return o
end

-- ── M.close() — scoped delete of ONLY the named overlay + ColorDef teardown ───
function M.close()
  local o = currentOverlay()
  if o then pcall(function()
    local ex = o:Find(NAME, "BaseInput"); if ex then ex:Parent():Delete(ex:Index()) end
  end) end
  cleanupColors()
end

-- ── small label helper ────────────────────────────────────────────────────────
local function label(parent, span, text, font, color)
  local u = parent:Append("UIObject"); u.Anchors = span; u.Text = text
  pcall(function()
    u.Font = font or "Regular16"; u.TextalignmentH = "Center"; u.TextalignmentV = "Center"
    u.HasHover = "No"; u.Focus = "Never"; if color then u.TextColor = color end
  end)
  return u
end

-- ── M.open() — mount the donation overlay on top of the current surface ───────
function M.open()
  local overlay = currentOverlay()
  if not overlay then return end
  M.close()   -- idempotent: never stack duplicates

  -- Encode the URL. Pin mask 6 (verified robustly scannable for this fixed URL).
  local enc
  local okEnc = pcall(function() enc = Snapshots.qrcode.encode(DONATION_URL, { mask = 6 }) end)
  if not okEnc or not enc then return end
  local m, size = enc.matrix, enc.size
  local grid_n  = size + QUIET * 2

  local black = makeColor("k", "000000FF")
  local white = makeColor("w", "FFFFFFFF")

  local root
  pcall(function()
    root = overlay:Append("BaseInput"); root.Name = NAME
    root.W, root.H = 540, 700
    root.AlignmentH, root.AlignmentV = "Center", "Center"
    root.Columns, root.Rows = 1, 2
    root.AutoClose, root.CloseOnEscape, root.AutoCloseOnOverlay = "Yes", "Yes", "Yes"
    root.OverrideKeybSC = "Yes"
    root.PluginComponent = my_handle
  end)
  if not root then return end
  pcall(function() local b = themeRef("surface"); if b then root.BackColor = b end end)
  pcall(function() root[1][1].SizePolicy = "Fixed"; root[1][1].Size = "45" end)
  pcall(function() root[1][2].SizePolicy = "Stretch" end)

  -- Title bar (close COLUMN is [2][2]).
  pcall(function()
    local tb = root:Append("TitleBar"); tb.Anchors, tb.Columns, tb.Rows = "0,0", 2, 1; tb.Texture = "corner2"
    pcall(function() tb[2][2].SizePolicy = "Fixed"; tb[2][2].Size = "50" end)
    local tt = tb:Append("TitleButton"); tt.Anchors = "0,0"; tt.Text = "Support Snapshots"; tt.Texture = "corner1"
    pcall(function() tt.TextColor = C.gold end)
    local cb = tb:Append("CloseButton"); cb.Anchors = "1,0"; cb.Texture = "corner2"
    cb.PluginComponent = my_handle; cb.Clicked = "OnDonateClose"
  end)

  -- Body frame + column grid (heading · QR · url · hint · buttons).
  local frame
  pcall(function()
    frame = root:Append("DialogFrame"); frame.Anchors = "0,1"; frame.H, frame.W = "100%", "100%"
    pcall(function() frame.Margin = "6,6,6,6"; frame.Texture = "frame15" end); frame.Columns, frame.Rows = 1, 1
  end)
  if not frame then return root end
  pcall(function() local b = themeRef("surface"); if b then frame.BackColor = b end end)

  local col
  pcall(function()
    col = frame:Append("UILayoutGrid"); col.Anchors = "0,0"; col.H, col.W = "100%", "100%"
    col.Columns, col.Rows = 1, 5
    col[1][1].SizePolicy = "Fixed"; col[1][1].Size = "34"     -- heading
    col[1][2].SizePolicy = "Stretch"                          -- QR (square, centered)
    col[1][3].SizePolicy = "Fixed"; col[1][3].Size = "30"     -- url text
    col[1][4].SizePolicy = "Fixed"; col[1][4].Size = "26"     -- hint
    col[1][5].SizePolicy = "Fixed"; col[1][5].Size = "46"     -- button row
  end)
  if not col then return root end

  label(col, { left = 0, right = 0, top = 0, bottom = 0 }, "If Snapshots helps your show, chip in", "Regular18", C.gold)
  label(col, { left = 0, right = 0, top = 2, bottom = 2 }, DONATION_URL, "Regular16", C.soft)
  label(col, { left = 0, right = 0, top = 3, bottom = 3 }, "(tap outside or press Esc to close)", "Regular14", C.soft)

  -- QR host: white UIObject backing (UILayoutGrid does NOT paint BackColor) under a transparent
  -- module grid; light modules + quiet zone show white, dark modules are black cells on top.
  local host
  pcall(function()
    host = col:Append("UILayoutGrid"); host.Anchors = { left = 0, right = 0, top = 1, bottom = 1 }
    host.H, host.W = "100%", "100%"; host.Columns, host.Rows = 1, 1
  end)
  if not host then return root end

  pcall(function()
    local back = host:Append("UIObject"); back.Anchors = "0,0"
    back.W, back.H = 444, 444
    back.AlignmentH, back.AlignmentV = "Center", "Center"
    pcall(function() back.HasHover = "No"; back.Focus = "Never" end)
    if white then back.BackColor = white end
  end)

  local panel
  pcall(function()
    panel = host:Append("UILayoutGrid"); panel.Anchors = "0,0"
    panel.W, panel.H = 444, 444
    panel.AlignmentH, panel.AlignmentV = "Center", "Center"
    panel.Columns, panel.Rows = grid_n, grid_n
  end)
  if panel then
    for r = 1, size do
      for c = 1, size do
        if m[r][c] then
          local cc = (c - 1) + QUIET
          local rr = (r - 1) + QUIET
          local qcell = panel:Append("UIObject")
          qcell.Anchors = { left = cc, right = cc, top = rr, bottom = rr }
          pcall(function() qcell.HasHover = "No"; qcell.Focus = "Never" end)
          if black then pcall(function() qcell.BackColor = black end) end
        end
      end
    end
  end

  -- Button row: Feedback + Close (Copy URL dropped — no clipboard seam in Snapshots).
  local btnRow
  pcall(function()
    btnRow = col:Append("UILayoutGrid"); btnRow.Anchors = { left = 0, right = 0, top = 4, bottom = 4 }
    btnRow.H, btnRow.W = "100%", "100%"; btnRow.Columns, btnRow.Rows = 2, 1
  end)
  if btnRow then
    local function tabBtn(colIdx, text, signal)
      local b = btnRow:Append("Button"); b.Anchors = { left = colIdx, right = colIdx, top = 0, bottom = 0 }
      b.Text = text; b.Font = "Regular16"
      b.PluginComponent = my_handle; b.Clicked = signal
      pcall(function() local t = themeRef("hover"); if t then b.BackColor = t end end)
      return b
    end
    tabBtn(0, "Feedback", "OnDonateFeedback")
    tabBtn(1, "Close", "OnDonateClose")
  end

  pcall(function() root:WaitInit(2); FindBestFocus(root) end)
  return root
end

-- ── signal wiring (file-scope signalTable) ────────────────────────────────────
signalTable.OnDonateClose    = function() M.close() end
-- Feedback: open the feedback form on top of the donation overlay (call-time lookup).
signalTable.OnDonateFeedback = function() pcall(function() Snapshots.ui.feedback.open() end) end

return M
