-- lib/store.lua (Snapshots.store) — THE persistence boundary module (PER-01..04 /
-- D-06). Persists the whole snapshot collection as a SINGLE JSON
-- string under one GlobalVars key "Snapshots"; survives show reload/reboot (host
-- proxy), merges per-id with a re-read-before-write delta so a stale writer cannot
-- clobber a peer station (PER-03), and degrades an absent/corrupt blob to empty
-- state without crashing (PER-04). Pattern: state load/save/clear,
-- extended with the per-id merge and the Snapshots_bak corrupt-backup.
--
-- BOUNDARY DISCIPLINE (the #1 rule, D-06 / RESEARCH Pitfall 6):
--   * PURE CORE (empty_state/encode/decode/merge_save/merge_delete) — plain
--     table<->string transforms; touch NO MA3 global; unit-testable with zero mock.
--   * BOUNDARY SHELL (load/save/delete/clear + _raw_get/_raw_set/_raw_backup/_notify)
--     — the ONLY functions that reach GlobalVars/GetVar/SetVar/DelVar/Printf, each
--     pcall-wrapped, and ONLY inside function bodies (never at load time).
-- Never load()/loadstring() a stored blob (code-injection hole) — json.decode only.
Snapshots = Snapshots or {}   -- idempotent bootstrap (NEVER `= {}` — wipes siblings)
local Store = {}

-- json is resolved guardedly: nil off-desk without the vendored lib is tolerated
-- (encode returns nil → save aborts; decode falls back to empty).
local json ; pcall(function() json = require("json") end)

-- ── PURE CORE ─────────────────────────────────────────────────────────────────
-- No MA3 reach; directly callable off-mock.

-- The lazy empty shape (PER-04): a versioned, snapshot-keyed collection.
function Store.empty_state()
  return { version = 1, snapshots = {} }
end

-- Serialize a state table → JSON string. The stored value MUST be a string
-- (Pitfall 2 / T-04-06); on any failure return nil so callers abort rather than
-- persist a table.
function Store.encode(state)
  if json == nil then return nil end
  local ok, s = pcall(json.encode, state)
  if not ok or type(s) ~= "string" then return nil end
  return s
end

-- Deserialize a stored blob. REPORTS corruption, does NOT act: returns
-- (state, corrupt_raw|nil). An absent/empty/undecodable blob → (empty_state, raw?)
-- and never errors (PER-04 / T-04-03). json.decode ONLY — never load()/loadstring().
function Store.decode(raw)
  if type(raw) ~= "string" or raw == "" then return Store.empty_state(), nil end
  if json == nil then return Store.empty_state(), nil end
  local ok, dec = pcall(json.decode, raw)
  if ok and type(dec) == "table" and type(dec.snapshots) == "table" then
    dec.version = dec.version or 1
    return dec, nil
  end
  return Store.empty_state(), raw   -- 2nd return = corrupt bytes for the shell to back up
end

-- Overlay ONLY the given id (Pitfall 5b: key by tostring(id) for string-key
-- discipline; rxi/json turns numeric keys into arrays otherwise).
function Store.merge_save(cur, id, data)
  cur.snapshots = cur.snapshots or {}
  cur.snapshots[tostring(id)] = data
  return cur
end

-- Remove ONLY the given id.
function Store.merge_delete(cur, id)
  cur.snapshots = cur.snapshots or {}
  cur.snapshots[tostring(id)] = nil
  return cur
end

-- ── BOUNDARY SHELL ──────────────────────────────────────────────────────────��─
-- The ONLY MA3 reach. Every primitive is pcall-wrapped inside its function body
-- (never at load — Pitfall 6). A load-race failure degrades gracefully (PER-04).
local KEY, BAK = "Snapshots", "Snapshots_bak"

-- Returns (ok, raw). ok=false means the GetVar/GlobalVars call itself FAILED (a
-- load-race hiccup); ok=true with raw=nil means the key is genuinely ABSENT.
-- Distinguishing these is essential on the write path (WR-01): degrading a read to
-- empty is safe, but degrading a read-BEFORE-write to empty would clobber peers.
function Store._raw_get()
  local raw
  local ok = pcall(function() raw = GetVar(GlobalVars(), KEY) end)
  return ok, raw
end

-- Normalize pcall's (ok, err?) to a SINGLE boolean (IN-02) so callers return one value.
function Store._raw_set(s)
  local ok = pcall(function() SetVar(GlobalVars(), KEY, s) end)
  return ok
end

function Store._raw_backup(raw)
  pcall(function() SetVar(GlobalVars(), BAK, raw) end)
end

function Store._notify(msg)
  pcall(function() Printf(msg) end)   -- nil Printf off-desk is harmless (pcall)
end

-- Internal read+decode of the live blob, handling corruption once (backup+notify).
-- Returns (read_ok, state). read_ok=false ⇒ the GetVar itself failed (load race) —
-- callers on the WRITE path MUST NOT persist in that case (WR-01). A genuinely
-- absent OR corrupt blob still yields read_ok=true with an empty state.
-- NOTE (IN-03): a *corrupt* (undecodable) blob during save/delete is unrecoverable
-- — its bytes are preserved to Snapshots_bak and the merge proceeds onto empty
-- state (peers in the corrupt blob are already lost). This is distinct from WR-01,
-- where the bytes are intact on disk and a mere read hiccup must NOT destroy them.
function Store._read()
  local ok, raw = Store._raw_get()
  local state, corrupt = Store.decode(raw)
  if corrupt then
    Store._raw_backup(corrupt)
    Store._notify("Snapshots: corrupt blob preserved to Snapshots_bak, starting empty")
  end
  return ok, state
end

-- Read the live blob → state. LENIENT: a failed read reads as empty (read-only,
-- so no data at risk). Never writes on the happy/absent path (lazy init, PER-04).
function Store.load()
  local _ok, state = Store._read()
  return state
end

-- Save one id: re-read the LIVE blob first (peers preserved), merge only this id,
-- write back as a JSON string (PER-03). Aborts WITHOUT writing on a failed read
-- (WR-01 — a transient GetVar hiccup must not clobber intact peers) or if encode
-- fails (never persists a table — T-04-06).
function Store.save(id, data)
  local ok, cur = Store._read()                        -- ◄── re-read-before-write (PER-03)
  if not ok then return false end                      -- ◄── WR-01: never write on a failed read
  local s = Store.encode(Store.merge_save(cur, id, data))
  if s == nil then return false end
  return Store._raw_set(s)
end

-- Delete one id: same re-read-before-write delta and read-failure guard as save.
function Store.delete(id)
  local ok, cur = Store._read()                        -- ◄── re-read-before-write (PER-03)
  if not ok then return false end                      -- ◄── WR-01: never write on a failed read
  local s = Store.encode(Store.merge_delete(cur, id))
  if s == nil then return false end
  return Store._raw_set(s)
end

-- Delete-all path: drop the whole key (leaves Snapshots_bak intact for recovery).
function Store.clear()
  pcall(function() DelVar(GlobalVars(), KEY) end)
end

Snapshots.store = Store   -- attach under the namespace key
return Store              -- RETURN THE TABLE (tests dofile it for this value)
