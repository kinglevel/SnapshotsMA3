-- lib/ui/feedback.lua (Snapshots.ui.feedback) — the feedback form overlay.
--
-- Collects a free-text message plus the auto-filled software name + version and POSTs them as
-- JSON to the community feedback endpoint via the shared HTTP transport (curl on onPC /
-- busybox-wget on the console). Opened from the About window and the donation overlay. Public
-- open()/close().
--
-- Sibling modules are NOT require-able, so the helpers are LIFTED here. There is no login/account
-- coupling. The message field is a native LineEdit (value = .Content) with the keyboard grabbed
-- (OverrideKeybSC) so physical keys land in it. The POST is a blocking call from the Send signal.
--
-- SCOPED-DISMISS: close() deletes ONLY this named BaseInput — NEVER a whole-overlay clear.
-- Global-namespace UI pattern. Varargs captured at FILE SCOPE. Every MA3 call pcall-wrapped.

Snapshots = Snapshots or {}
Snapshots.ui = Snapshots.ui or {}
local M = {}
Snapshots.ui.feedback = M

local signalTable = select(3, ...)
local my_handle   = select(4, ...)

local SOFTWARE     = "Snapshots"
-- Community feedback endpoint (one swappable constant). Expects JSON { softwarename, version,
-- issue, email } (all required) → 201 on success, 429 when the per-IP rate limit is hit, 400 on a
-- missing/empty field or a malformed email (we validate the email client-side to avoid the round-trip).
local FEEDBACK_URL = "http://community.smidn.com/feedback"
local NAME = "SnapshotsFeedback"

local C = { gold = "Global.Selected", soft = "Global.Bright" }
local function themeRef(role) local r; pcall(function() r = Snapshots.ui.theme and Snapshots.ui.theme.ref(role) end); return r end
local function applyBg(w, role) if not w then return end pcall(function() local r = themeRef(role); if r then w.BackColor = r end end) end

-- version string (Snapshots.version is a TABLE — read .STRING at call time).
local function version()
  local v = "2.0.0.0"
  pcall(function() if Snapshots.version and Snapshots.version.STRING then v = Snapshots.version.STRING end end)
  return tostring(v)
end

local function currentOverlay() local o; pcall(function() o = GetFocusDisplay().ScreenOverlay end); return o end

-- module-scope handles so the Send/close signal handlers can read the field + update status
M._edit, M._status = nil, nil

-- ── M.close() — scoped delete of ONLY the named overlay ───────────────────────
function M.close()
  local o = currentOverlay()
  if o then pcall(function()
    local ex = o:Find(NAME, "BaseInput"); if ex then ex:Parent():Delete(ex:Index()) end
  end) end
  M._edit, M._email, M._status = nil, nil, nil
end

-- ── do_send() — POST { softwarename, version, issue } to the endpoint ─────────
-- Mirror the collector's email check (server isValidEmail): exactly one "@", non-empty local part,
-- a dotted domain, no whitespace. JS /^[^\s@]+@[^\s@]+\.[^\s@]+$/ → Lua pattern below. Validating
-- here avoids a round-trip 400 and gives a clear inline message.
local function valid_email(s)
  return type(s) == "string" and s:match("^[^%s@]+@[^%s@]+%.[^%s@]+$") ~= nil
end

local function do_send()
  local msg = ""
  if M._edit then pcall(function() msg = M._edit.Content or "" end) end
  msg = tostring(msg)
  local email = ""
  if M._email then pcall(function() email = M._email.Content or "" end) end
  email = tostring(email):gsub("^%s+", ""):gsub("%s+$", "")   -- trim (server rejects surrounding space)
  local function setStatus(text, role)
    if not M._status then return end
    pcall(function()
      M._status.Text = text
      M._status.TextColor = (role == "err") and (themeRef("red") or C.gold) or (themeRef("cyan") or C.gold)
    end)
  end
  if email == "" then setStatus("Please enter your email so we can follow up.", "err"); return end
  if not valid_email(email) then setStatus("That email doesn't look right — please check it.", "err"); return end
  if msg:gsub("%s", "") == "" then setStatus("Please enter some feedback first.", "err"); return end

  setStatus("Sending…", "ok")
  -- Field names match the community collector contract: softwarename / version / issue / email (all required).
  local payload = { softwarename = SOFTWARE, version = version(), issue = msg, email = email }
  local ua = "User-Agent: SnapshotsMA3/" .. version()
  local ok, res = pcall(function()
    return Snapshots.http.post_json(FEEDBACK_URL, payload, { headers = { ua }, max_time = 15 })
  end)
  local st = (ok and res and res.status) and tostring(res.status) or nil
  local success = st ~= nil and st:match("^2%d%d$") ~= nil          -- 201 = stored
  if success then
    setStatus("Thanks! Your feedback was sent.", "ok")
    if M._edit then pcall(function() M._edit.Content = "" end) end
  elseif st == "429" then
    setStatus("You've sent feedback recently — please wait a little and try again.", "err")
  elseif st == "400" then
    setStatus("Please check your email and feedback, then try again.", "err")
  elseif st == nil then
    setStatus("Couldn't reach the feedback server. Check your connection and try again.", "err")
  else
    setStatus("Couldn't send (status " .. tostring(st) .. "). Please try again later.", "err")
  end
end

-- ── M.open() — mount the feedback overlay on top of the current surface ───────
function M.open()
  local overlay = currentOverlay()
  if not overlay then return end
  M.close()   -- idempotent

  local root
  pcall(function()
    root = overlay:Append("BaseInput"); root.Name = NAME
    root.W, root.H = 580, 540
    root.AlignmentH, root.AlignmentV = "Center", "Center"
    root.Columns, root.Rows = 1, 2
    -- Has a LineEdit + keyboard grab → no native AutoClose/CloseOnEscape (which risk a
    -- CloseOK-while-handler crash); Escape closes via the KeyDown handler instead.
    root.AutoClose, root.CloseOnEscape, root.OverrideKeybSC = "No", "No", "Yes"
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
    local tt = tb:Append("TitleButton"); tt.Anchors = "0,0"; tt.Text = "Send Feedback"; tt.Texture = "corner1"
    pcall(function() tt.TextColor = C.gold end)
    local cb = tb:Append("CloseButton"); cb.Anchors = "1,0"; cb.Texture = "corner2"
    cb.PluginComponent = my_handle; cb.Clicked = "OnFeedbackClose"
  end)

  local frame
  pcall(function() frame = root:Append("DialogFrame"); frame.Anchors = "0,1"; frame.H, frame.W = "100%", "100%"
    pcall(function() frame.Margin = "6,6,6,6"; frame.Texture = "frame15" end); frame.Columns, frame.Rows = 1, 1 end)
  if not frame then return root end
  applyBg(frame, "surface")

  local grid
  pcall(function()
    grid = frame:Append("UILayoutGrid"); grid.Anchors = "0,0"; grid.H, grid.W = "100%", "100%"
    grid.Columns, grid.Rows = 1, 8
    -- 1 software · 2 version · 3 "your email" · 4 email field · 5 "your feedback" · 6 message (stretch) · 7 status · 8 buttons
    local function rowH(i, px) pcall(function() grid[1][i].SizePolicy = "Fixed"; grid[1][i].Size = tostring(px) end) end
    rowH(1, 28); rowH(2, 28); rowH(3, 26); rowH(4, 44); rowH(5, 26)
    pcall(function() grid[1][6].SizePolicy = "Stretch" end)
    rowH(7, 26); rowH(8, 46)
  end)
  if not grid then return root end

  local function label(span, text, font, color)
    local u = grid:Append("UIObject"); u.Anchors = span; u.Text = text
    pcall(function() u.Font = font or "Regular16"; u.TextalignmentH = "Left"; u.TextalignmentV = "Center"
      u.HasHover = "No"; u.Focus = "Never"; if color then u.TextColor = color end end)
    return u
  end

  -- Auto-filled context (shown so the user sees exactly what is sent with their message).
  label({ left = 0, right = 0, top = 0, bottom = 0 }, "  Software:   " .. SOFTWARE,   "Regular16", C.soft)
  label({ left = 0, right = 0, top = 1, bottom = 1 }, "  Version:    v" .. version(), "Regular16", C.soft)
  label({ left = 0, right = 0, top = 2, bottom = 2 }, "  Your email:",                "Regular16", C.gold)

  -- Email field (required by the collector so we can follow up). Native LineEdit; force it to FILL
  -- its fixed row (ContentHeight=Yes otherwise collapses it to ~8px, same trap as the topbar search).
  local emailEdit
  pcall(function()
    emailEdit = grid:Append("LineEdit"); emailEdit.Anchors = { left = 0, right = 0, top = 3, bottom = 3 }
    emailEdit.Content = ""
    pcall(function() emailEdit.ContentHeight = "No"; emailEdit.H = "100%" end)
    emailEdit.Font = "Regular18"
    emailEdit.PluginComponent = my_handle; emailEdit.KeyDown = "OnFeedbackKey"; emailEdit.KeyUp = "OnFeedbackKeyUp"
  end)
  applyBg(emailEdit, "row")
  M._email = emailEdit

  label({ left = 0, right = 0, top = 4, bottom = 4 }, "  Your feedback:",             "Regular16", C.gold)

  -- Message field (native LineEdit; physical keys land here via OverrideKeybSC).
  local edit
  pcall(function()
    edit = grid:Append("LineEdit"); edit.Anchors = { left = 0, right = 0, top = 5, bottom = 5 }
    edit.Content = ""
    edit.PluginComponent = my_handle; edit.KeyDown = "OnFeedbackKey"; edit.KeyUp = "OnFeedbackKeyUp"
  end)
  applyBg(edit, "row")
  M._edit = edit

  local status = label({ left = 0, right = 0, top = 6, bottom = 6 }, "", "Regular14", C.soft)
  pcall(function() status.TextalignmentH = "Center" end)
  M._status = status

  -- Button row: Send (primary) + Cancel.
  local btnRow
  pcall(function()
    btnRow = grid:Append("UILayoutGrid"); btnRow.Anchors = { left = 0, right = 0, top = 7, bottom = 7 }
    btnRow.H, btnRow.W = "100%", "100%"; btnRow.Columns, btnRow.Rows = 2, 1
  end)
  if btnRow then
    local sendBtn = btnRow:Append("Button"); sendBtn.Anchors = { left = 0, right = 0, top = 0, bottom = 0 }
    sendBtn.Text = "Send"; sendBtn.Font = "Regular18"
    sendBtn.PluginComponent = my_handle; sendBtn.Clicked = "OnFeedbackSend"
    applyBg(sendBtn, "hover"); pcall(function() sendBtn.TextColor = themeRef("cyan") or C.gold end)
    local cancelBtn = btnRow:Append("Button"); cancelBtn.Anchors = { left = 1, right = 1, top = 0, bottom = 0 }
    cancelBtn.Text = "Cancel"; cancelBtn.Font = "Regular18"
    cancelBtn.PluginComponent = my_handle; cancelBtn.Clicked = "OnFeedbackClose"
    applyBg(cancelBtn, "hover")
  end

  pcall(function() root:WaitInit(2); FindBestFocus(M._email or edit or root) end)
  return root
end

-- ── signal wiring (file-scope signalTable) ────────────────────────────────────
signalTable.OnFeedbackClose = function() M.close() end
signalTable.OnFeedbackSend  = function() do_send() end
signalTable.OnFeedbackKey   = function(caller, _, keycode)
  if keycode == 256 then M.close() end   -- Escape closes (Enter left alone — synthetic Enter can crash)
end
signalTable.OnFeedbackKeyUp = function() end

return M
