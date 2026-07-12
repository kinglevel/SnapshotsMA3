-- lib/ui/about.lua (Snapshots.ui.about) — the standalone About window overlay.
--
-- A dedicated About window (its OWN named BaseInput — "SnapshotsAbout"), opened from the
-- manager topbar's About button (OnAbout → Snapshots.ui.about.open()). Shows the plugin name +
-- version (read at CALL time from Snapshots.version.STRING) and the credit "by Kinglevel", plus
-- a ♥ Donate + Feedback row and Close.
--
-- Sibling modules are NOT require-able, so the small helpers are LIFTED here.
-- SCOPED-DISMISS: close() deletes ONLY this named BaseInput
-- (ex:Parent():Delete(ex:Index())) — NEVER a whole-overlay clear (that would wipe the
-- manager). Donate/Feedback delegate at CALL time to Snapshots.ui.donate/feedback.open().
--
-- Global-namespace UI pattern. Varargs captured at FILE SCOPE — the file MUST NOT touch any MA3
-- global at load time, only inside function bodies; every reach pcall-wrapped. Appends ONLY
-- verified widget classes (BaseInput/TitleBar/TitleButton/CloseButton/DialogFrame/UILayoutGrid/
-- UIObject/Button).

Snapshots = Snapshots or {}
Snapshots.ui = Snapshots.ui or {}
local M = {}
Snapshots.ui.about = M

local signalTable = select(3, ...)
local my_handle   = select(4, ...)

local NAME = "SnapshotsAbout"   -- named overlay (scoped delete on dismiss)

-- Vetted stock text refs (TextColor accepts a named-string ref).
local C = { gold = "Global.Selected", soft = "Global.Bright" }

-- theme.ref(role) at call time (pcall-guarded — nil off-desk / pre-install).
local function themeRef(role)
  local r; pcall(function() r = Snapshots.ui.theme and Snapshots.ui.theme.ref(role) end); return r
end
local function applyBg(w, role)
  if not w then return end
  pcall(function() local r = themeRef(role); if r then w.BackColor = r end end)
end

-- version string (Snapshots.version is a TABLE — read .STRING at call time).
local function version()
  local v = "2.0.0.0"
  pcall(function() if Snapshots.version and Snapshots.version.STRING then v = Snapshots.version.STRING end end)
  return tostring(v)
end

-- ── small layout helpers (lifted verbatim trio) ──────────────────────────────
local function rowH(g, i, px) pcall(function() g[1][i].SizePolicy="Fixed"; g[1][i].Size=tostring(px) end) end

local function cell(parent, span, text, font, align, color)
  local u = parent:Append("UIObject"); u.Anchors = span
  if text then u.Text = text end
  u.Font = font or "Regular16"
  pcall(function() u.TextalignmentH = align or "Left"; u.TextalignmentV = "Center"; u.HasHover = "No"; u.Focus = "Never"
    if color then u.TextColor = color end end)
  return u
end

local function currentOverlay()
  local overlay; pcall(function() overlay = GetFocusDisplay().ScreenOverlay end); return overlay
end

-- ── M.close() — delete ONLY the named overlay (manager stays intact) ──────────
function M.close()
  local overlay = currentOverlay()
  if not overlay then return end
  pcall(function()
    local ex = overlay:Find(NAME, "BaseInput")
    if ex then ex:Parent():Delete(ex:Index()) end
  end)
end

-- ── M.open() — mount the About window on top of the manager ───────────────────
function M.open()
  local overlay = currentOverlay()
  if not overlay then return end
  M.close()   -- idempotent: never stack duplicates

  local root
  pcall(function()
    root = overlay:Append("BaseInput"); root.Name = NAME
    root.W, root.H = 460, 500
    root.AlignmentH, root.AlignmentV = "Center", "Center"
    root.Columns, root.Rows = 1, 2
    root.AutoClose, root.CloseOnEscape, root.AutoCloseOnOverlay = "Yes", "Yes", "Yes"
    root.OverrideKeybSC = "Yes"
    root.PluginComponent = my_handle
  end)
  if not root then return end
  applyBg(root, "surface")
  pcall(function() root[1][1].SizePolicy = "Fixed"; root[1][1].Size = "45" end)
  pcall(function() root[1][2].SizePolicy = "Stretch" end)

  -- Title bar (close COLUMN is [2][2]).
  pcall(function()
    local tb = root:Append("TitleBar"); tb.Anchors, tb.Columns, tb.Rows = "0,0", 2, 1; tb.Texture = "corner2"
    pcall(function() tb[2][2].SizePolicy = "Fixed"; tb[2][2].Size = "50" end)
    local tt = tb:Append("TitleButton"); tt.Anchors = "0,0"; tt.Text = "About"; tt.Texture = "corner1"
    pcall(function() tt.TextColor = C.gold end)
    local cb = tb:Append("CloseButton"); cb.Anchors = "1,0"; cb.Texture = "corner2"
    cb.PluginComponent = my_handle; cb.Clicked = "OnAboutClose"
  end)

  -- Body frame + grid.
  local frame
  pcall(function()
    frame = root:Append("DialogFrame"); frame.Anchors = "0,1"; frame.H, frame.W = "100%", "100%"
    pcall(function() frame.Margin = "4,4,4,4"; frame.Texture = "frame15" end); frame.Columns, frame.Rows = 1, 1
  end)
  if not frame then return root end
  applyBg(frame, "surface")

  local grid
  -- Rows: 1 icon · 2 name+version · 3 credit · 4 spacer(stretch) · 5 Donate/Feedback · 6 Close.
  pcall(function()
    grid = frame:Append("UILayoutGrid"); grid.Anchors = "0,0"; grid.H, grid.W = "100%", "100%"
    grid.Columns, grid.Rows = 1, 6
    rowH(grid, 1, 150); rowH(grid, 2, 40); rowH(grid, 3, 30)
    pcall(function() grid[1][4].SizePolicy = "Stretch" end)
    rowH(grid, 5, 46); rowH(grid, 6, 46)
  end)
  if not grid then return root end

  -- Decorative fader badge (Snapshots stores fader/master positions). `.Texture` FILLS+SCALES the
  -- cell (a `.Icon` would stay a fixed small glyph); the monochrome mask is
  -- multiplied by BackColor, so we tint it with the cyan accent. Non-interactive.
  pcall(function()
    local ic = grid:Append("Button"); ic.Anchors = { left = 0, right = 0, top = 0, bottom = 0 }
    pcall(function() ic.W = 130; ic.H = 130; ic.AlignmentH = "Center"; ic.AlignmentV = "Center" end)
    pcall(function() ic.Texture = "fader" end)
    pcall(function() local r = themeRef("cyan"); if r then ic.BackColor = r end end)
    pcall(function() ic.HasHover = "No"; ic.Focus = "Never"; ic.Enabled = "No" end)
  end)

  cell(grid, { left = 0, right = 0, top = 1, bottom = 1 },
       "Snapshots MA3  ·  v" .. version(), "Regular18", "Center", C.gold)
  cell(grid, { left = 0, right = 0, top = 2, bottom = 2 }, "by Kinglevel", "Regular16", "Center", C.soft)

  -- Donate + Feedback row (side by side).
  local btnRow
  pcall(function()
    btnRow = grid:Append("UILayoutGrid"); btnRow.Anchors = { left = 0, right = 0, top = 4, bottom = 4 }
    btnRow.H, btnRow.W = "100%", "100%"; btnRow.Columns, btnRow.Rows = 2, 1
  end)
  if btnRow then
    local donateBtn = btnRow:Append("Button"); donateBtn.Anchors = { left = 0, right = 0, top = 0, bottom = 0 }
    donateBtn.Text = "♥ Donate"; donateBtn.Font = "Regular18"
    donateBtn.PluginComponent = my_handle; donateBtn.Clicked = "OnAboutDonate"
    applyBg(donateBtn, "hover"); pcall(function() donateBtn.TextColor = themeRef("cyan") or C.gold end)
    local fbBtn = btnRow:Append("Button"); fbBtn.Anchors = { left = 1, right = 1, top = 0, bottom = 0 }
    fbBtn.Text = "Feedback"; fbBtn.Font = "Regular18"
    fbBtn.PluginComponent = my_handle; fbBtn.Clicked = "OnAboutFeedback"
    applyBg(fbBtn, "hover")
  end

  -- Close button.
  local closeBtn
  pcall(function()
    closeBtn = grid:Append("Button"); closeBtn.Anchors = { left = 0, right = 0, top = 5, bottom = 5 }
    closeBtn.Text = "Close"; closeBtn.Font = "Regular18"
    closeBtn.PluginComponent = my_handle; closeBtn.Clicked = "OnAboutClose"
  end)
  applyBg(closeBtn, "hover")

  pcall(function() root:WaitInit(2); FindBestFocus(root) end)
  return root
end

-- ── signal wiring (file-scope signalTable) ────────────────────────────────────
signalTable.OnAboutClose    = function() M.close() end
-- Donate/Feedback delegate at CALL time (siblings are not require-able); each is its own scoped
-- BaseInput mounted on top of About; dismissing it returns here.
signalTable.OnAboutDonate   = function() pcall(function() Snapshots.ui.donate.open() end) end
signalTable.OnAboutFeedback = function() pcall(function() Snapshots.ui.feedback.open() end) end

return M
