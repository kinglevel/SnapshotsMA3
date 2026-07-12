-- lib/ui/theme.lua — custom ColorGroup swatch registry (Snapshots v2, UI-01/UI-04).
--
-- The Snapshots manager palette as MA3 ColorTheme swatches.
-- MA3's `widget.BackColor` takes ONLY a ColorGroup ref (never a hex string —
-- assigning a string silently no-ops), so to paint the manager chrome in the
-- palette hexes we create a custom ColorDef (holds the RGBA) + a ColorGroup entry
-- (references the def via .ColorDefRef); that entry is the ref BackColor consumes.
--
--   install()  — idempotent find-or-create the two SnapshotsColors groups
--                (ColorDefCollect + ColorGroups) and every role entry. Reload
--                never duplicates: every level is `:Find(name) or :Acquire()`.
--                No-op off-desk (Root()/ColorTheme absent).
--   ref(name)  — the cached ColorGroup ref for a role, or nil (callers pcall-guard
--                the BackColor assign and fall back to a stock ref / default on nil).
--   teardown() — delete every acquired ColorDef + ColorGroup entry and both
--                SnapshotsColors groups (find-by-name → Obj.Delete). Wired into
--                the manager's OnClose so the swatches never persist in the
--                showfile (T-07-08). Idempotent + safe to call twice.
--
-- Because these mutate the GLOBAL Root().ColorTheme (which is saved with the
-- show), teardown() on close is a hard obligation (T-07-08). Global-namespace UI
-- pattern; varargs captured at FILE SCOPE — the file MUST NOT touch any MA3 global
-- at load time, only inside function bodies. Every MA3 call pcall-wrapped.

Snapshots = Snapshots or {}
Snapshots.ui = Snapshots.ui or {}
local M = {}
Snapshots.ui.theme = M

local signalTable = select(3, ...)
local my_handle   = select(4, ...)

-- The named ColorDefCollect / ColorGroups group both created under this name so a
-- teardown can find-and-delete exactly what install created.
local CT = "SnapshotsColors"

-- The swatch roles + exact hex (07-UI-SPEC Theme Mapping). Order is stable so
-- acquire/teardown walk the same set. RGBA wants "RRGGBBAA" so append "FF".
-- The Phase-8 chip/fader roles are DEFINED NOW (used later by panes 2/3 when they go
-- live) so their refs already resolve and are torn down by teardown() — do not remove.
local PALETTE = {
  { role = "bg",         hex = "0C0D0F" },   -- window backdrop
  { role = "surface",    hex = "17191C" },   -- pane panels
  { role = "row",        hex = "1F2226" },   -- resting list-row surface
  { role = "hover",      hex = "282C31" },   -- hover / raised
  { role = "cyan",       hex = "16C5E6" },   -- selection stripe + selected-row tint
  { role = "amber",      hex = "F2A52B" },   -- "breakdown" sub-line / warnings
  { role = "red",        hex = "E2483D" },   -- Delete… label
  { role = "textDim",    hex = "61666E" },   -- headers, sub-lines, badges
  -- Phase-8 roles: DEFINE NOW, used later (07-UI-SPEC) — do not remove
  { role = "chipExec",     hex = "2F6EDE" },
  { role = "chipSequence", hex = "1FA588" },   -- Sequences (teal)
  { role = "chipPreset",   hex = "C24D8C" },   -- Presets (magenta)
  { role = "chipGroup",    hex = "7A45D1" },
  { role = "chipMaster",   hex = "C9772A" },
  { role = "faderTrack", hex = "101215" },
  { role = "faderFill",  hex = "16C5E6" },
}

-- Cached ColorGroup refs keyed by role. Populated by install(), cleared by teardown().
local _refs = {}

-- find-or-create a named child under a ColorTheme collection (idempotent).
local function acquireNamed(parent, name)
  local found = parent:Find(name)
  if found then return found end
  local g = parent:Acquire()
  g.Name = name
  return g
end

-- ── install() — idempotent create of the swatch registry ──────────────────────
-- find-or-create both groups + each role entry, set the def RGBA, LINK the group
-- entry to its def (ColorDefRef — the magic), and cache the ref. A second call
-- re-finds everything (no duplicate groups/entries accumulate across reloads). A
-- safe no-op when Root()/ColorTheme is absent (host tests / pre-init).
function M.install()
  pcall(function()
    local root = Root()
    local theme = root and root.ColorTheme
    if not theme then return end
    local collect = theme.ColorDefCollect
    local groups  = theme.ColorGroups
    if not (collect and groups) then return end

    local defGrp = acquireNamed(collect, CT)   -- ColorDefCollect group (holds the RGBAs)
    local cgGrp  = acquireNamed(groups,  CT)   -- ColorGroups group (holds the refs)

    for _, p in ipairs(PALETTE) do
      local cd = acquireNamed(defGrp, p.role)
      pcall(function() cd:Set("RGBA", p.hex .. "FF") end)
      local ref = acquireNamed(cgGrp, p.role)
      pcall(function() ref.ColorDefRef = cd end)   -- the LINK BackColor consumes
      _refs[p.role] = ref
    end
  end)
end

-- ── ref(name) — the cached ColorGroup ref for a role (nil on miss) ────────────
-- Callers assign it to a widget's BackColor inside a pcall and fall back to a
-- stock ref / widget default when this returns nil (never install-coupled; pure lookup).
function M.ref(name)
  return _refs[name]
end

-- ── teardown() — delete every acquired swatch + both groups (T-07-08) ─────────
-- Find both SnapshotsColors groups by name, delete each role entry (reverse-safe via
-- Obj.Index), then delete the group itself — for BOTH the ColorGroups and the
-- ColorDefCollect side. Idempotent: absent groups → nothing deleted. Safe to call
-- twice (OnClose may run more than once). Drops the ref cache last.
function M.teardown()
  pcall(function()
    local root = Root()
    local theme = root and root.ColorTheme
    if not theme then return end

    local function purge(parent)
      if not parent then return end
      local grp = parent:Find(CT)
      if not grp then return end
      for _, p in ipairs(PALETTE) do
        local e = grp:Find(p.role)
        if e then pcall(function() Obj.Delete(grp, Obj.Index(e)) end) end
      end
      pcall(function() Obj.Delete(parent, Obj.Index(grp)) end)
    end

    purge(theme.ColorGroups)      -- the refs
    purge(theme.ColorDefCollect)  -- the defs
  end)
  _refs = {}
end

return M
