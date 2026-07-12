-- lib/num.lua (Snapshots.num) — the single home for fader float-epsilon logic.
-- SP4 proved a set-to-60 fader reads back 59.999996, so every value comparison in
-- model/fade/tests must share ONE epsilon instead of scattering
-- `math.abs(a-b)<0.01`. PURE module — touches no MA3 global (boundary policy D-06).
Snapshots = Snapshots or {}   -- idempotent bootstrap (NEVER `= {}` — wipes siblings)
local Num = {}

Num._EPS = 1e-3   -- default float tolerance (SP4: 59.999996 vs 60 -> diff ~4e-6)

-- True when |a-b| is within eps. Default eps 1e-3 tolerates SP4 float imprecision.
function Num.approx_eq(a, b, eps)
  eps = eps or Num._EPS
  return math.abs(a - b) <= eps
end

-- Bound v into the closed range [lo, hi].
function Num.clamp(v, lo, hi)
  if v < lo then return lo elseif v > hi then return hi else return v end
end

-- Snap a float-imprecise fader read to its nearest integer (59.999996 -> 60).
function Num.round_fader(v)
  return math.floor(v + 0.5)
end

Snapshots.num = Num   -- attach under the namespace key
return Num            -- RETURN THE TABLE (tests dofile it for this value)
