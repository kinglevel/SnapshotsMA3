-- lib/breakdown.lua — Snapshots.breakdown (RCL-05, D-11..D-13).
-- Breakdown-override target selector: when a recall carries the `breakdown`
-- flag it OVERRIDES stored values and drives every eligible assigned object to
-- 100. Two pure functions — is_excluded_master (D-12) + select_targets (D-13).
-- PURE MODULE: touches zero MA3 console globals. SHARED-A skeleton; SHARED-C
-- defensive addr parse; SHARED-B call-time sibling cross-ref.
Snapshots = Snapshots or {}
local Breakdown = {}

-- Data-driven exclusion set (constant-table convention). Category numbering is
-- VERIFIED from PROBE-FINDINGS §SP4. MG2 "Grand" holds BOTH the 8 level masters
-- (targets) AND the cat-2 timing entries (excluded below).
Breakdown.EXCLUDED_CATEGORIES = { [3] = true, [4] = true, [5] = true }  -- Speed, Playback, Timing
Breakdown.EXCLUDED_CAT2 = { [6] = true, [8] = true, [9] = true, [10] = true, [11] = true, [15] = true }
-- (2.6 Rate, 2.8 ProgramTime, 2.9 ProgramXFade, 2.10 ExecutorTime, 2.11 ExecutorXFade, 2.15 SoundFade)

-- is_excluded_master(ref) — true when ref is a timing/speed/rate master that
-- breakdown must NOT drive to 100 (RCL-05). Parses the addr DEFENSIVELY
-- (Pitfall 6 — never tonumber(addr)); a non-master / malformed addr → false.
-- The 8 level masters (incl. Grand 2.1) fall through → NOT excluded (D-12).
function Breakdown.is_excluded_master(ref)
  local c, n = tostring(ref.addr):match("Master%s+(%d+)%.(%d+)")
  c, n = tonumber(c), tonumber(n)
  if not c then return false end                    -- not a master addr → not excluded here
  if Breakdown.EXCLUDED_CATEGORIES[c] then return true end
  if c == 2 and Breakdown.EXCLUDED_CAT2[n] then return true end
  return false                                       -- cat-2 level masters (incl. Grand 2.1) → included
end

-- select_targets(plan) — from a recall plan [{ref,value},…] emit
-- [{ref,to=100},…] for every breakdown-eligible object. Eligibility is
-- CATEGORY-based, NOT type-based (D-13): executors, sequences, presets and
-- groups are always targets; masters are targets UNLESS is_excluded_master
-- filters them. Stored value is OVERRIDDEN to 100 (D-11). The sibling predicate
-- is resolved at CALL time (SHARED-B) via Snapshots.breakdown.is_excluded_master.
function Breakdown.select_targets(plan)
  local out = {}
  for _, p in ipairs(plan) do
    local ref = p.ref
    if ref.type == "master" then
      if not Snapshots.breakdown.is_excluded_master(ref) then
        out[#out + 1] = { ref = ref, to = 100 }
      end
    else
      out[#out + 1] = { ref = ref, to = 100 }
    end
  end
  return out
end

Snapshots.breakdown = Breakdown
return Breakdown
