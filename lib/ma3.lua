-- lib/ma3.lua (Snapshots.ma3) — THE console-adapter boundary module, READ side
-- (OBJ-02 / CAP-01/02/03/05). The single choke point where the plugin touches the
-- live MA3 console: a pool walk that builds a byGuid index (OBJ-02), GUID-only
-- resolution with skip+notify on a miss (NO address fallback — locked decision),
-- and live-fader capture via GetFader({token="FaderMaster"}) for groups, level-type
-- special masters and GUID-bearing executor hosts. The fade-apply (tween) half —
-- recall / RCL-02 apply — lands in Plan 05-03 on top of these exact seams.
--
-- BOUNDARY DISCIPLINE (the #1 rule, D-06 / RESEARCH Pitfall 8):
--   * PURE CORE (setfader_args/index_from_pairs/resolve/is_capturable) — plain
--     table transforms + a GUID lookup + a call-time predicate reuse; touch NO MA3
--     global; unit-testable with zero mock; this file loads MA-free under the bare
--     harness.
--   * BOUNDARY SHELL (read_fader/write_fader/notify/build_by_guid/capture) — the
--     ONLY functions that reach Root/GetFader/SetFader/Printf, each pcall-wrapped,
--     and ONLY inside function bodies (never at load time).
--
-- Two correctness rules encoded here:
--   * GUID-ONLY resolution: resolve returns nil on a miss AND when ref.guid is nil
--     — there is NO address fallback; the caller does skip+notify and continues (a
--     moved object must never be driven by its old address) (T-05-03).
--   * CAP-01 is PARTIAL by design: an executor SLOT exposes no GUID (SP3). Executor
--     masters are captured via their GUID-bearing hosted object (sequence/preset/
--     group); a bare exec slot keyed by address only resolves to nil → skip+notify.
--
-- Cross-module refs (breakdown/num) are resolved at CALL time (Snapshots.x.y(...)),
-- never captured as load-time upvalues (sibling load order is not
-- guaranteed).
Snapshots = Snapshots or {}   -- idempotent bootstrap (NEVER `= {}` — wipes siblings)
local Ma3 = {}

-- ── PURE CORE ─────────────────────────────────────────────────────────────────
-- No MA3 reach; directly callable off-mock.

-- The EXACT SetFader table shape (RCL-02 apply contract) — an instant set carries
-- NO time field (a time= key would make the write itself a fade — Pitfall 1). The
-- tween in 05-03 drives value over many of these instant writes, not one timed one.
function Ma3.setfader_args(value)
  return { value = value, token = "FaderMaster" }
end

-- Build a byGuid map from a [{guid,handle},…] list. Keep ONLY string, non-empty
-- guids; nil/empty/placeholder guids are dropped (OBJ-02; re-filters build_by_guid's
-- own guard so a malformed pair can never pollute the index — T-05-05).
function Ma3.index_from_pairs(pairs_list)
  local byGuid = {}
  for _, p in ipairs(pairs_list) do
    if type(p.guid) == "string" and p.guid ~= "" then byGuid[p.guid] = p.handle end
  end
  return byGuid
end

-- Build typed schema refs from a [{guid,label,addr},…] list (ASGN-04/05/06). Keeps
-- ONLY string, non-empty, ≠"nil" guids — a bare exec slot (GUID nil/"nil", live-
-- verified SP3/Pitfall 2) can NEVER become an addr-keyed member, so recall follows
-- the object when it moves and never mis-drives a re-laid slot (T-08-01, LOCKED
-- GUID-only). The param is `kind` (NOT `type`) so the `type()` builtin guard still
-- resolves; construction goes through Snapshots.schema.new_ref at CALL time (single
-- ref-build path, validates kind ∈ TYPES). Mirrors index_from_pairs' filter.
function Ma3.refs_from_pairs(pairs_list, kind)
  local out = {}
  for _, p in ipairs(pairs_list) do
    if type(p.guid) == "string" and p.guid ~= "" and p.guid ~= "nil" then
      out[#out + 1] = Snapshots.schema.new_ref{
        guid = p.guid, addr = p.addr, label = p.label, type = kind,
      }
    end
  end
  return out
end

-- GUID-ONLY resolution (T-05-03, locked): the handle on a GUID hit, nil on a miss
-- OR when ref.guid is nil. There is NO address fallback — the caller skip+notifies
-- and continues so a re-laid-out object is never mis-driven by a stale address.
function Ma3.resolve(ref, byGuid)
  if not ref or not ref.guid then return nil end
  return byGuid[ref.guid]
end

-- CAP-03 capture eligibility: non-master types are always capturable; a master is
-- capturable UNLESS it is a speed/time/rate/xfade master. REUSES the Phase-3
-- predicate at call time (no re-derived category logic here — single source of
-- truth, no drift with the SP4-verified exclusion set).
function Ma3.is_capturable(ref)
  if ref.type == "master" then
    return not Snapshots.breakdown.is_excluded_master(ref)
  end
  return true
end

-- ── BOUNDARY SHELL ──────────────────────────────────────────────────────────────
-- The ONLY MA3 reach. Every primitive is pcall-wrapped inside its function body
-- (never at load — Pitfall 8). A load-race failure degrades gracefully: a nil read
-- (skip+notify) or an empty/partial index, never a crash (T-05-04).

-- Read one handle's live 0..100 fader value. Returns the number, or nil if the
-- GetFader call itself failed (caller treats nil as an unreadable object).
function Ma3.read_fader(handle)
  local v
  local ok = pcall(function() v = handle:GetFader({ token = "FaderMaster" }) end)
  if ok then return v end
  return nil
end

-- Write one handle's fader to an instant value (used by 05-03's tween). Call-time
-- cross-ref to setfader_args for the exact table shape.
function Ma3.write_fader(handle, value)
  pcall(function() handle:SetFader(Snapshots.ma3.setfader_args(value)) end)
end

-- Skip+notify to the System Monitor (Printf). A nil Printf off-desk is harmless (pcall).
-- UI-03: ALSO mirror the skip/notify line onto the monitor strip — Ma3.notify is the
-- RCL-06 seam that bypasses deps.notify, so the strip would silently drop every skip
-- line unless it is fed here too. `msg` is ALREADY "Snapshots: …" (its callers prefix
-- it), so push it VERBATIM — never cross-route through Snapshots.log (double-prefix).
-- Call-time guarded (`if Snapshots.monitor`) + pcall → an absent monitor degrades
-- silently and never crashes the invocation (T-09-10/11).
function Ma3.notify(msg)
  pcall(function() if Snapshots.monitor then Snapshots.monitor.push(msg) end end)
  pcall(function() Printf(msg) end)                                    -- UNCHANGED
end

-- Current showfile identity — the loaded show's file name (e.g. "MyShow"), read from
-- Root().ManetSocket.Showfile (the accessor the firmware system-tests use; the .show
-- suffix is stripped if present). This is the ONLY signal that changes when a different
-- show is loaded: nothing in the Lua VM resets on a show reload (module locals + UserVars
-- all survive per the lifecycle survival matrix), so the "is this a fresh show?" check
-- compares this live value against a remembered one. Returns a non-empty string, or nil
-- when unreadable/empty (off-desk, load race) — callers treat nil as "unknown, do nothing".
function Ma3.current_showfile()
  local name
  pcall(function() name = Root().ManetSocket.Showfile end)
  if type(name) ~= "string" then return nil end
  name = (name:gsub("%.show$", ""))
  if name == "" then return nil end
  return name
end

-- Walk the live-verified pool tree and build the byGuid index (OBJ-02). Each child
-- is guarded by Get("GUID",0); only string, non-empty, ≠"nil" guids are kept, so a
-- placeholder slot (Pitfall 4: :Children() returns 13 slots for 1 real sequence)
-- never enters the index. The WHOLE walk is one pcall — a load-race degrades to a
-- partial/empty index (T-05-04). Assembly is delegated to the pure index_from_pairs.
function Ma3.build_by_guid()
  local pairs_list = {}
  local function add(handle)
    local g
    pcall(function() g = handle:Get("GUID", 0) end)
    if type(g) == "string" and g ~= "" and g ~= "nil" then
      pairs_list[#pairs_list + 1] = { guid = g, handle = handle }
    end
  end
  pcall(function()
    for _, dp in ipairs(Root().ShowData.DataPools:Children()) do
      if dp.Groups     then for _, o in ipairs(dp.Groups:Children())     do add(o) end end
      if dp.Sequences  then for _, o in ipairs(dp.Sequences:Children())  do add(o) end end
      if dp.PresetPools then
        for _, pool in ipairs(dp.PresetPools:Children()) do
          for _, o in ipairs(pool:Children()) do add(o) end          -- presets nest one level deeper
        end
      end
    end
    for _, cat in ipairs(Root().ShowData.Masters:Children()) do
      for _, m in ipairs(cat:Children()) do add(m) end
    end
  end)
  return Snapshots.ma3.index_from_pairs(pairs_list)                    -- pure assembly
end

-- Enumerate a pool's GUID-bearing objects as typed refs (ASGN-04 browse). Extends
-- the build_by_guid walk, reading Get("Name",0) as the display label (and, for
-- masters, the addr the exclusion filter parses). kind ∈ {"executor","group",
-- "master"}:
--   * "group"    → each datapool .Groups:Children()
--   * "executor" → each datapool .Sequences:Children() + .PresetPools→pool:Children()
--                  (presets nest one level deeper — Pitfall 5)
--   * "master"   → Root().ShowData.Masters:Children()→cat:Children(), filtered by
--                  Snapshots.breakdown.is_excluded_master at CALL time so only the 8
--                  level masters are listed (speed/time/rate/xfade dropped — CAP-03 reuse).
-- The WHOLE walk is ONE pcall (a load-race degrades to a partial/empty list, never a
-- crash — T-08-05); each Get is its own inner pcall. Assembly (and the GUID drop of a
-- no-GUID slot) is delegated to the pure refs_from_pairs seam.
-- Map an MA3 object class name to a Snapshots ref type (PURE). An executor is only a
-- LOCATOR — the object on the fader keeps its REAL type (and pane colour). Substring match
-- so class variants ("CuePool"/"SequPool"/"PresetPool…") still resolve; unknowns fall back to
-- "executor" so an oddball fader object still lists rather than vanishing.
function Ma3.class_to_type(cls)
  local c = tostring(cls or ""):lower()
  if c:find("sequ", 1, true) or c:find("cue", 1, true) then return "sequence"
  elseif c:find("group", 1, true)  then return "group"
  elseif c:find("preset", 1, true) then return "preset"
  else return "executor" end
end

-- Enumerate the show's datapools as { {index=i, name=..}, .. } for the pane's datapool selector.
function Ma3.datapools()
  local out = {}
  pcall(function()
    for i, dp in ipairs(Root().ShowData.DataPools:Children()) do
      local nm; pcall(function() nm = dp:Get("Name", 0) end)
      out[#out + 1] = { index = i, name = (type(nm) == "string" and nm ~= "" and nm) or ("Datapool " .. i) }
    end
  end)
  return out
end

-- The 1-based position (in DataPools:Children()) of the CURRENTLY selected datapool — DataPool()
-- returns the live/selected pool; matched by GUID. nil off-desk / on error. Used to default the
-- pane's datapool selector to the pool the operator is already working in.
function Ma3.current_datapool_index()
  local idx
  pcall(function()
    local cur = DataPool()
    local curG; pcall(function() curG = cur:Get("GUID", 0) end)
    local i = 0
    for _, dp in ipairs(Root().ShowData.DataPools:Children()) do
      i = i + 1
      if dp == cur then idx = i
      elseif curG then
        local g; pcall(function() g = dp:Get("GUID", 0) end)
        if g == curG then idx = i end
      end
    end
  end)
  return idx
end

-- pool_objects(kind [, dp_index]): dp_index (1-based) scopes the group/sequence/preset walk to a
-- single datapool; nil walks ALL datapools (executor/master ignore it — they span pages / are global).
function Ma3.pool_objects(kind, dp_index)
  -- "Executor masters" = the objects ACTUALLY ON executor faders, enumerated via each page's
  -- executors → GetAssignedObj() (the GUID-bearing hosted object; firmware systemtests/db/
  -- system_test_exec_move.lua). A bare slot returns nil and is skipped. Each is typed by its
  -- REAL class (class_to_type) so the pane shows MIXED types in MIXED colours and a fader object
  -- that's also a group still counts/ticks as a group (identity is GUID — assign.object_rows).
  if kind == "executor" then
    local out, seen = {}, {}   -- dedupe by GUID: the SAME object on several faders is ONE entry
    pcall(function()
      for _, dp in ipairs(Root().ShowData.DataPools:Children()) do
        if dp.Pages then
          for _, pg in ipairs(dp.Pages:Children()) do
            for _, ex in ipairs(pg:Children()) do
              local o
              pcall(function() o = ex:GetAssignedObj() end)
              if o then
                local g, nm, cls
                pcall(function() g   = o:Get("GUID", 0) end)
                pcall(function() nm  = o:Get("Name", 0) end)
                pcall(function() cls = o:GetClass() end)
                if type(g) == "string" and g ~= "" and g ~= "nil" and not seen[g] then
                  seen[g] = true
                  out[#out + 1] = Snapshots.schema.new_ref{
                    guid = g, addr = nm, label = nm, type = Snapshots.ma3.class_to_type(cls),
                  }
                end
              end
            end
          end
        end
      end
    end)
    return out
  end

  local pairs_list = {}
  local function add(handle, is_master)
    local g, nm
    pcall(function() g  = handle:Get("GUID", 0) end)
    pcall(function() nm = handle:Get("Name", 0) end)
    -- masters: the Name IS the "Master C.N" address the exclusion filter parses;
    -- drop excluded (speed/time/rate/xfade) masters BEFORE they enter the list.
    if is_master and Snapshots.breakdown.is_excluded_master({ addr = nm }) then return end
    pairs_list[#pairs_list + 1] = { guid = g, label = nm, addr = nm }
  end
  -- walk ALL datapools, or just the dp_index-th when the pane's selector has picked one (ipairs
  -- pick, not a raw numeric index into the :Children() result — robust to non-array child tables).
  local function eachDP(fn)
    local i = 0
    for _, dp in ipairs(Root().ShowData.DataPools:Children()) do
      i = i + 1
      if (not dp_index) or (i == dp_index) then fn(dp) end
    end
  end
  pcall(function()
    if kind == "group" then
      eachDP(function(dp) if dp.Groups then for _, o in ipairs(dp.Groups:Children()) do add(o) end end end)
    elseif kind == "sequence" then
      eachDP(function(dp) if dp.Sequences then for _, o in ipairs(dp.Sequences:Children()) do add(o) end end end)
    elseif kind == "preset" then
      eachDP(function(dp)
        if dp.PresetPools then
          for _, pool in ipairs(dp.PresetPools:Children()) do
            for _, o in ipairs(pool:Children()) do add(o) end             -- presets nest deeper
          end
        end
      end)
    elseif kind == "master" then
      for _, cat in ipairs(Root().ShowData.Masters:Children()) do
        for _, m in ipairs(cat:Children()) do add(m, true) end             -- filter excluded masters
      end
    end
  end)
  return Snapshots.ma3.refs_from_pairs(pairs_list, kind)                    -- pure assembly
end

-- Pool sizes for the Type-pane `in_show` counts (ASGN-04). Counts GUID-bearing
-- objects per category — reuses pool_objects so the GUID/exclusion filters apply
-- identically (single source of truth). Returns { executor=N, group=N, master=N }.
function Ma3.pool_counts()
  return {
    executor = #Snapshots.ma3.pool_objects("executor"),
    sequence = #Snapshots.ma3.pool_objects("sequence"),
    preset   = #Snapshots.ma3.pool_objects("preset"),
    group    = #Snapshots.ma3.pool_objects("group"),
    master   = #Snapshots.ma3.pool_objects("master"),
  }
end

-- Resolve a command-line address to typed refs (ASGN-05 page/range · ASGN-06 group).
-- ObjectList("<addr>") yields the objects the operator addressed; a Group/Sequence/
-- Master carries a GUID (assigned), but a bare Executor SLOT returns GUID nil (live-
-- verified, Pitfall 2) — that handle is DROPPED by the pure seam AND fires a
-- skip+notify to the System Monitor so the operator sees why the slot was not added.
-- ObjectList reach is in-body + pcall-wrapped (T-08-05); assembly is the pure seam.
function Ma3.objects_from_addr(addr, kind)
  local pairs_list = {}
  pcall(function()
    for _, hnd in ipairs(ObjectList(addr) or {}) do
      local g, nm
      pcall(function() g  = hnd:Get("GUID", 0) end)
      pcall(function() nm = hnd:Get("Name", 0) end)
      if type(g) ~= "string" or g == "" or g == "nil" then
        Snapshots.ma3.notify("Snapshots: skip (no GUID) " .. tostring(addr))
      end
      pairs_list[#pairs_list + 1] = { guid = g, label = nm, addr = addr }
    end
  end)
  return Snapshots.ma3.refs_from_pairs(pairs_list, kind)                    -- pure assembly (drops no-GUID)
end

-- Capture the live values of a ref list (CAP-01/02/03/05). Builds a fresh index,
-- and for each CAPTURABLE ref resolves it by GUID, reads its live fader, and rounds
-- via num.round_fader (SP4: a set-to-60 fader reads 59.999996). A GUID miss fires
-- skip+notify and CONTINUES — one unresolvable object never aborts the capture
-- (OBJ-02). Excluded masters are filtered by is_capturable before any read (CAP-03).
-- Returns [{ref,value},…]. (Executor bare slots resolve to nil → skip+notify: the
-- deferred CAP-01 case; exec masters are captured via their GUID-bearing host.)
function Ma3.capture(refs)
  local byGuid = Snapshots.ma3.build_by_guid()
  local out = {}
  for _, ref in ipairs(refs) do
    if Snapshots.ma3.is_capturable(ref) then
      local handle = Snapshots.ma3.resolve(ref, byGuid)
      if handle then
        local v = Snapshots.ma3.read_fader(handle)
        if v ~= nil then
          out[#out + 1] = { ref = ref, value = Snapshots.num.round_fader(v) }
        end
      else
        Snapshots.ma3.notify("Snapshots: capture skip (GUID miss) " .. tostring(ref.label or ref.addr))
      end
    end
  end
  return out
end

-- ── FADE-APPLY (RCL-02) ─────────────────────────────────────────────────────────
-- The uniform Lua value-animation engine — the WRITE side of the choke point.
-- recall drives every assigned, GUID-resolvable object from its live value toward
-- its stored value over fade_time, uniformly across ALL object types (NO native
-- Fade / command-line At — object-dependent, SP1-reversed). One Timer drives ONE
-- shared scalar u:0→100; each tick writes Snapshots.fade.interp(from,to,u) (the
-- reused PURE math — no inline interpolation here). Correctness rules encoded:
--   * Instant-set fallback (fade<=0 / nil / no Timer) writes the EXACT stored `to`
--     immediately — a recall ALWAYS reaches the stored end state (A4).
--   * Generation guard (Ma3._gen): MA3 Timer returns no cancel handle, so a bumped
--     counter cancels a superseded recall — a stale tick/done from an overtaken
--     recall no-ops (Pitfall 3). done() re-applies exact `to` only when still current.
-- BOUNDARY: Timer/Time reached ONLY inside this body (never at load — Pitfall 8),
-- each MA3 write via the pcall-wrapped write_fader seam; siblings at call time.

Ma3._gen = 0            -- monotonic recall generation; a bump cancels the prior tween

-- Timer step (~25fps). Fractional interval is live-proven (Pitfall 2). UAT-tunable:
-- a smaller value renders smoother at the cost of more writes/sec on the console.
local INTERVAL = 0.04

-- pcall-guarded monotonic clock read (boundary consistency — IN-01). Returns 0 if
-- Time() is unavailable/errors; callers gate the tween on Time being a function so a
-- 0 here never produces a from=0 fade jump (IN-02).
local function _now()
  local t = 0 ; pcall(function() t = Time() end) ; return t
end

-- recall(plan, fade_time) — RCL-02 apply. `plan` is model.recall_plan output:
-- [{ ref=<schema ref>, value=0..100 }, …] (assigned-only). Resolves each ref by
-- GUID against a FRESH pool walk, reads its live `from` once, and drives it to `to`.
function Ma3.recall(plan, fade_time)
  Ma3._gen = Ma3._gen + 1        -- WR-01: ANY new recall (instant OR tween) supersedes a
  local my_gen = Ma3._gen        -- pending tween — bump before the instant-set branch, not after.
  local byGuid = Snapshots.ma3.build_by_guid()
  local targets = {}
  for _, p in ipairs(plan) do
    local handle = Snapshots.ma3.resolve(p.ref, byGuid)
    if handle then
      targets[#targets + 1] = { h = handle, from = Snapshots.ma3.read_fader(handle) or 0, to = p.value }
    else
      Snapshots.ma3.notify("Snapshots: recall skip (GUID miss) " .. tostring(p.ref.label or p.ref.addr))
    end
  end
  if #targets == 0 then return end

  -- writes the exact stored `to` for every target (instant-set path AND done()).
  local function apply_final()
    for _, t in ipairs(targets) do Snapshots.ma3.write_fader(t.h, t.to) end
  end

  -- Instant-set: fade<=0 / nil / no scheduler / no usable clock → one exact write pass.
  -- (_gen already bumped above, so any prior tween now no-ops.)
  if not fade_time or fade_time <= 0 or type(Timer) ~= "function" or type(Time) ~= "function" then
    apply_final()
    return
  end

  local t0 = _now()
  local iterations = math.max(1, math.ceil(fade_time / INTERVAL))

  local function tick()
    if Ma3._gen ~= my_gen then return end        -- superseded → stop writing (Pitfall 3)
    local u = ((_now() - t0) / fade_time) * 100
    if u >= 100 then u = 100 end
    for _, t in ipairs(targets) do
      Snapshots.ma3.write_fader(t.h, Snapshots.fade.interp(t.from, t.to, u))   -- reused pure math
    end
  end

  local function done()
    if Ma3._gen == my_gen then apply_final() end  -- exact land only when still current
  end

  pcall(function() Timer(tick, INTERVAL, iterations, done) end)
end

Snapshots.ma3 = Ma3   -- attach under the namespace key
return Ma3            -- RETURN THE TABLE (tests dofile it for this value)
