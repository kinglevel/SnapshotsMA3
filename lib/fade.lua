-- lib/fade.lua (Snapshots.fade) — the PURE TWEEN MATH (D-01 / D-02 / D-03).
-- This is value-interpolation only, NOT a command-string builder: the dead
-- keyword approach was reversed by Phase 2 (SP1) in favour of a uniform Lua
-- value animation. interp(from,to,u) = from+(to-from)*(u/100) with exact
-- endpoints (no float drift at u<=0 / u>=100). build_targets emits {ref,to}
-- pairs only — the live starting value is read from the live console in Phase 5,
-- never here. resolve_time (RCL-03) lets a recall arg override the snapshot default.
-- PURE module — touches no MA3 global (boundary policy D-06). Any rounding is a
-- call-time Snapshots.num.round_fader lookup (SHARED-B), never a duplicated epsilon.
Snapshots = Snapshots or {}   -- idempotent bootstrap (NEVER `= {}` — wipes siblings)
local Fade = {}

-- Linear interpolation of a single scalar. u is progress in [0..100]. The exact
-- endpoint guards return the stored bounds verbatim (no float drift) and clamp
-- any out-of-range progress so a value can never overshoot the target (T-03-09).
function Fade.interp(from, to, u)
  if u <= 0 then return from end        -- exact endpoint / clamp low
  if u >= 100 then return to end        -- exact endpoint / clamp high
  return from + (to - from) * (u / 100)
end

-- Map a recall plan (model.recall_plan output) to animation target pairs. Emits
-- {ref, to=value} only — the starting value is injected live by Phase 5 from the
-- live console, so it is deliberately absent here.
function Fade.build_targets(plan)
  local t = {}
  for _, p in ipairs(plan) do
    t[#t + 1] = { ref = p.ref, to = p.value }
  end
  return t
end

-- RCL-03: a numeric recall arg overrides the per-snapshot default fade; anything
-- non-numeric (or nil) falls back to the default, and a nil default resolves to 0.
function Fade.resolve_time(snapshot_default, arg_fade)
  if type(arg_fade) == "number" then return arg_fade end
  return snapshot_default or 0
end

Snapshots.fade = Fade   -- attach under the namespace key
return Fade             -- RETURN THE TABLE (tests dofile it for this value)
