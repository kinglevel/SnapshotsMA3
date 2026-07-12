-- lib/args.lua (Snapshots.args) — operator command parser (D-04..D-07, D-14 / RCL-03).
-- Turns an arg string into a structured `intent`, or fails loud with {code,msg}.
-- Grammar: <verb> <name> [key=value ...] [flag ...]
--   verb ∈ {recall,store,clear} (case-insensitive, D-04)
--   name is the token after the verb; quotable for spaces (D-05)
--   key=value (fade=3 → number) + bare flags (breakdown), any order after name (D-05/D-06)
--   malformed → structured error, never a silent default (D-07)
-- BOUNDARY: pure logic — touches NO MA3 global and NEVER logs; it returns the error
-- for the caller (Phase 6 dispatch) to surface via sysmon.
-- Skeleton: SHARED-A (bootstrap+attach+return) + SHARED-C (pcall-guarded string helpers).
Snapshots = Snapshots or {}   -- idempotent bootstrap (NEVER `= {}` — wipes siblings)
local Args = {}

-- ── SHARED-C: pcall-guarded string helpers (Snapshots.lua:9-12) ──────────────
local function safe_tostring(v)
  local ok, s = pcall(tostring, v); if ok and s then return s end; return ""
end
local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- ── Stable error codes (Phase-6 sysmon depends on these strings; RESEARCH Pat.2) ─
local ERR = { UNKNOWN_VERB = "unknown_verb", MISSING_NAME = "missing_name",
              UNKNOWN_KEY = "unknown_key",  UNKNOWN_FLAG = "unknown_flag",
              BAD_FADE = "bad_fade",        EMPTY = "empty" }

local VERBS = { recall = true, store = true, clear = true }

-- Tokenize honoring double-quotes as a single token. Bounded scans only:
-- an unterminated quote degrades to a normal token (T-03-06 — no infinite loop).
local function tokenize(s)
  local tokens, i, n = {}, 1, #s
  while i <= n do
    local c = s:sub(i, i)
    if c:match("%s") then
      i = i + 1
    elseif c == '"' then
      local close = s:find('"', i + 1, true)
      if close then
        tokens[#tokens + 1] = s:sub(i + 1, close - 1)
        i = close + 1
      else
        tokens[#tokens + 1] = s:sub(i + 1)   -- unterminated quote → rest as one token
        i = n + 1
      end
    else
      local j = i
      while j <= n and not s:sub(j, j):match("%s") do j = j + 1 end
      tokens[#tokens + 1] = s:sub(i, j - 1)
      i = j
    end
  end
  return tokens
end

-- parse(arg_str) -> intent | nil, {code, msg}
function Args.parse(arg_str)
  local s = trim(safe_tostring(arg_str))
  if s == "" then return nil, { code = ERR.EMPTY, msg = "empty arg" } end

  local tokens = tokenize(s)

  local verb = tokens[1] and tokens[1]:lower() or ""
  if not VERBS[verb] then
    return nil, { code = ERR.UNKNOWN_VERB, msg = "unknown verb '" .. (tokens[1] or "") .. "'" }
  end

  local name = tokens[2]
  if not name or trim(name) == "" then
    return nil, { code = ERR.MISSING_NAME, msg = "missing snapshot name" }
  end

  local intent = { verb = verb, name = name }

  for i = 3, #tokens do
    local tok = tokens[i]
    local key, val = tok:match("^([^=]+)=(.*)$")
    if key then
      if key == "fade" then
        local num = tonumber(val)
        if not num then
          return nil, { code = ERR.BAD_FADE, msg = "fade= must be numeric, got '" .. val .. "'" }
        end
        intent.fade = num
      else
        return nil, { code = ERR.UNKNOWN_KEY, msg = "unknown key '" .. key .. "'" }
      end
    elseif tok == "breakdown" then
      intent.breakdown = true
    else
      return nil, { code = ERR.UNKNOWN_FLAG, msg = "unknown flag '" .. tok .. "'" }
    end
  end

  return intent
end

-- ── build(spec) — the exact inverse of parse (Phase-6 bar + macro share ONE grammar) ─
-- spec = { verb="recall"|"store"|"clear", name=<string>, fade=<number?>, snap=<bool?>,
--          breakdown=<bool?> } → the arg string that parse() accepts, so
-- parse(build(spec)) ≡ spec (proven by tests/test_args.lua round-trip block).
--   • name is ALWAYS double-quoted → a spaced name stays ONE token (parse de-quotes it).
--   • snap=true ⇒ fade=0 (RCL-04 global Snap = instant set), overriding any spec.fade.
--   • nil fade + snap false ⇒ NO fade= emitted → the stored default applies (RCL-03).
--   • breakdown is appended ONLY for the recall verb.
--   • fade is formatted with %g so 3.0→"3" (never "fade=3.0"), 2.5→"2.5".
-- Known limitation — a snapshot name containing a literal `"` cannot round-trip (the
-- parser has no escape; the first `"` closes the token). Constrain names upstream:
-- no double-quotes in snapshot names (09-RESEARCH Open Q1 / Pitfall 4).
-- BOUNDARY: pure — reaches for NO MA3 global and NEVER logs.
local function fmt_fade(n) return string.format("%g", n) end   -- 3.0→"3", 2.5→"2.5", 0→"0"
local function quote(name) return '"' .. safe_tostring(name) .. '"' end
function Args.build(spec)
  spec = spec or {}
  local verb  = spec.verb or "recall"
  local parts = { verb, quote(spec.name) }
  if verb == "recall" then
    if spec.snap then
      parts[#parts + 1] = "fade=0"
    elseif type(spec.fade) == "number" then
      parts[#parts + 1] = "fade=" .. fmt_fade(spec.fade)
    end
    if spec.breakdown then parts[#parts + 1] = "breakdown" end
  end
  return table.concat(parts, " ")
end

Snapshots.args = Args
return Args
