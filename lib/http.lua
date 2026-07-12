-- lib/http.lua (Snapshots.http) — the single, host-testable network seam.
--
-- A minimal HTTP seam, trimmed to the POST path the feedback form
-- needs. Keeps BOTH backends (curl on Mac/Windows onPC, busybox wget on the console) so a
-- feedback POST works multiplatform through ONE popen() boundary with per-backend,
-- injection-safe quoting:
--   * value escaping (curl -K, double-quote) + single-quoting (busybox wget)
--   * a scalar allowlist (validate_scalars) on every value that reaches argv/config
--   * an injectable runner seam (_real_runner / M._runner) so the SAME code runs under busted
--   * per-request temp-file cleanup so no request body lingers
--
-- Not ported (unneeded here): download / download_async / check_download / poll_async / get
-- (the binary-download surface Snapshots has no use for).
--
-- TRAN-01: this is the ONLY file in the codebase that references the process boundary
-- (the popen call) or the curl/wget tool names. All other modules call Snapshots.http.* — they
-- never shell out.
--
-- Global-namespace pattern (no require for siblings). Cross-module refs are CALL-TIME
-- (Snapshots.paths.tempDirRoot() inside a function body), never a file-scope capture
-- (load-order race). NEVER touches an MA3 global at module load.

Snapshots = Snapshots or {}   -- idempotent bootstrap (NEVER `= {}` — wipes siblings)
local M = {}
Snapshots.http = M

-- ── Request headers ─────────────────────────────────────────────────────────
-- A neutral browser-like User-Agent + Accept. Callers (e.g. the feedback form) append their
-- own headers; browser_headers() is only the fallback default.
local UA      = "User-Agent: Mozilla/5.0 (compatible; SnapshotsMA3)"
local ACCEPT  = "Accept: application/json, text/plain, */*"
local CT_JSON = "Content-Type: application/json"

-- Fresh table each call so a caller may append without mutating the constant.
function M.browser_headers()
  return { UA, ACCEPT }
end

local Q = string.char(34)   -- curl -K honors DOUBLE quotes only (single => exit 23)

local ALLOWED_METHODS = { GET = true, POST = true, HEAD = true }

-- ── Scalar allowlists (ME-01) ───────────────────────────────────────────────
-- The only variable scalars that may flow toward argv/config: cookie, rid, method.
-- Validate before either backend builds anything.
function M.valid_phpsessid(id) return tostring(id):match("^[A-Za-z0-9]+$") ~= nil end
function M.valid_rid(rid)      return tostring(rid):match("^%d+$") ~= nil end

local function validate_scalars(req)
  if req.cookie ~= nil and not M.valid_phpsessid(req.cookie) then
    return nil, "invalid cookie (allowlist ^[A-Za-z0-9]+$)"
  end
  if req.rid ~= nil and not M.valid_rid(req.rid) then
    return nil, "invalid rid (allowlist ^%d+$)"
  end
  if req.method ~= nil and not ALLOWED_METHODS[req.method] then
    return nil, "method not allowlisted: " .. tostring(req.method)
  end
  return true
end

-- curl -K value escaping (ME-01): double-quote only; escape \ and " and REJECT [\r\n]
-- (a newline would inject a second config directive).
local function esc(v)
  v = tostring(v)
  if v:find("[\r\n]") then return nil, "value contains newline" end
  return (v:gsub("\\", "\\\\"):gsub(Q, "\\" .. Q))
end

-- ── build_config(req) -> cfg_path, cfg_text | nil, err (curl backend) ───────
-- Writes an injection-safe curl -K config; ALL values escaped + double-quoted; body via
-- @file, output/dump-header to files; per-request timeout; NO redirect-follow unless
-- req.follow_redirect.
function M.build_config(req)
  local okv, verr = validate_scalars(req)
  if not okv then return nil, verr end

  local lines = {}
  local rejected
  local function opt(k, v)
    if rejected then return end
    local ev, eerr = esc(v)
    if ev == nil then rejected = eerr; return end
    lines[#lines + 1] = k .. " = " .. Q .. ev .. Q
  end

  opt("url", req.url)
  if req.method then lines[#lines + 1] = "request = " .. req.method end
  local headers = req.headers or {}
  for _, h in ipairs(headers) do opt("header", h) end
  if req.cookie then opt("header", "Cookie: PHPSESSID=" .. req.cookie) end
  if req.body_file then opt("data-binary", "@" .. req.body_file) end   -- body OFF argv (TRAN-05)
  if req.out then opt("output", req.out) end                          -- body -> file (binary-safe)
  if req.dump_header then opt("dump-header", req.dump_header) end      -- response headers captured here

  if rejected then return nil, rejected end

  local mt = math.floor(tonumber(req.max_time) or 30)
  local ct = math.floor(tonumber(req.connect_timeout) or 10)
  lines[#lines + 1] = "max-time = " .. mt
  lines[#lines + 1] = "connect-timeout = " .. ct
  lines[#lines + 1] = "silent"
  lines[#lines + 1] = "show-error"
  if req.follow_redirect then lines[#lines + 1] = "location" end       -- curl -L
  opt("write-out", "status=%{http_code} verify=%{ssl_verify_result} redirs=%{num_redirects}")
  if rejected then return nil, rejected end

  local cfg_text = table.concat(lines, "\n") .. "\n"

  local dir = req._workdir or Snapshots.paths.tempDirRoot()
  local cfg_path = req._cfg_path or (dir .. "/snap_req.cfg")
  local f, ferr = io.open(cfg_path, "w")
  if not f then return nil, "cannot write cfg: " .. tostring(ferr) end
  f:write(cfg_text)
  f:close()
  return cfg_path, cfg_text
end

-- ── parse_response(hdr_path, out_path) -> table ────────────────────────────
-- Pure Lua, no MA3 globals. status / Set-Cookie / 3xx-count / HTML-peek. out_path may be nil.
function M.parse_response(hdr_path, out_path)
  local function slurp(pth)
    if not pth then return "" end
    local fh = io.open(pth, "rb"); if not fh then return "" end
    local d = fh:read("*a"); fh:close(); return d or ""
  end
  local hdr = slurp(hdr_path)
  local status    = hdr:match("HTTP/%d%.%d%s+(%d+)")
  local phpsessid = hdr:match("[Ss]et%-[Cc]ookie:%s*PHPSESSID=([^;%s]+)")
  local location  = hdr:match("[Ll]ocation:%s*([^\r\n]+)")
  local _, redirs = hdr:gsub("HTTP/%d%.%d%s+3%d%d", "")
  local body      = slurp(out_path):sub(1, 256)
  local body_is_html = body:match("^%s*<[!%a]") ~= nil
  return { status = status, phpsessid = phpsessid, location = location, redirects = redirs, body_is_html = body_is_html }
end

-- ── The process boundary as an INJECTABLE runner (D-03) ─────────────────────
-- The ONLY place a child process is spawned. request() calls (req.runner or M._runner); busted injects
-- a fake runner so no child process ever spawns under test.
function M._real_runner(cmd)
  local p = io.popen(cmd)
  local stdout = p:read("*a")
  local ok, kind, code = p:close()   -- Lua 5.4 triple — capture ALL three
  return stdout, ok, kind, code
end
M._runner = M._real_runner

-- ── backend() — pick the HTTPS tool per host ────────────────────────────────
-- Owned HERE (not paths.lua) so this remains the SOLE file naming the curl/wget tools
-- (TRAN-01). curl on onPC (Mac/Windows); busybox wget on the console. Any non-Mac/Windows
-- label AND the nil case (HostOS raised) default to wget. Reads the raw host label via the
-- paths shim (paths.hostOS()), keeping the MA3-globals pcall in one place.
function M.backend()
  local h = Snapshots.paths.hostOS()
  if h == "Mac" or h == "Windows" then return "curl" end
  return "wget"
end

-- ── request(req) -> res ─────────────────────────────────────────────────────
-- The one interface. Dispatches curl (build_config) vs wget (build_argv) on M.backend();
-- runs the command through the injectable runner; parses the response; then ALWAYS cleans up
-- its per-request temp files.
function M.request(req)
  req = req or {}
  local paths = Snapshots.paths
  local res = { ok = false }

  -- Per-request workdir for the control temps (cfg / dump-header / body). Fall back to the
  -- temp root if lfs mkdir is unavailable.
  local okmk, workdir = pcall(paths.makeTempDir)
  if not okmk then workdir = nil end
  local dir = workdir or paths.tempDirRoot()

  local hdr_path = req.dump_header or (dir .. "/resp.hdr")
  local out_path = req.out or (dir .. "/resp.body")
  local loose    = {}   -- temp paths to os.remove when we could not use a workdir

  pcall(function()
    local backend = M.backend()

    local reqx = {}
    for k, v in pairs(req) do reqx[k] = v end
    reqx.dump_header = hdr_path
    reqx.out         = out_path
    reqx._workdir    = dir

    local cmd
    if backend == "curl" then
      reqx._cfg_path = dir .. "/snap_req.cfg"
      local cfg_path, berr = M.build_config(reqx)
      if not cfg_path then res.error = berr; return end
      loose[#loose + 1] = cfg_path
      cmd = "curl -K " .. Q .. cfg_path .. Q
    else
      local argv, berr = M.build_argv(reqx)
      if not argv then res.error = berr; return end
      cmd = argv
    end

    local runner = req.runner or M._runner
    local stdout, rok, rkind, rcode = runner(cmd)
    res.stdout   = stdout
    res.exit_ok  = (rok == true)
    res.exit_code = rcode

    local parsed = M.parse_response(hdr_path, out_path)
    res.status       = parsed.status
    res.phpsessid    = parsed.phpsessid
    res.location     = parsed.location
    res.redirects    = parsed.redirects
    res.body_is_html = parsed.body_is_html
    res.header_path  = hdr_path
    res.body_path    = out_path

    -- Transport-level success: clean process exit. Gate downstream logic on it.
    res.ok = res.exit_ok and (rcode == 0 or rcode == nil)

    -- Small text bodies are read into res.body before cleanup so callers never depend on the
    -- (soon-removed) temp file.
    if not req._no_body_read then
      local bf = io.open(out_path, "rb")
      if bf then res.body = bf:read("*a"); bf:close() end
    end
  end)

  -- Always-runs cleanup: remove the whole per-run subdir (cfg + dump-header + body all live
  -- under it) so nothing lingers. Caller-supplied out/dump_header paths live OUTSIDE the
  -- workdir and are the caller's to own.
  if workdir then pcall(function() paths.removeDir(workdir) end) end
  for _, p in ipairs(loose) do pcall(os.remove, p) end

  return res
end

-- ── Minimal JSON encoder — host-test fallback when firmware json is absent ──
local function json_escape(s)
  return (tostring(s):gsub('[%z\1-\31\\"]', function(c)
    local m = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }
    return m[c] or string.format('\\u%04x', c:byte())
  end))
end

function M._encode_json(tbl)
  local parts = {}
  for k, v in pairs(tbl) do
    local val
    if type(v) == "string" then
      val = '"' .. json_escape(v) .. '"'
    elseif type(v) == "boolean" or type(v) == "number" then
      val = tostring(v)
    else
      val = '"' .. json_escape(tostring(v)) .. '"'
    end
    parts[#parts + 1] = '"' .. json_escape(k) .. '":' .. val
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

-- ── post_json(url, tbl, opts) -> res ────────────────────────────────────────
-- Encodes tbl with the firmware json (fallback to _encode_json off-desk), writes a 0600 temp
-- body_file, POSTs with Content-Type: application/json and follow_redirect=false, then ALWAYS
-- os.remove's the body.
function M.post_json(url, tbl, opts)
  opts = opts or {}

  local json_text
  local ok = pcall(function()
    local json = require("json")
    json_text = json.encode(tbl)
  end)
  if not ok or type(json_text) ~= "string" then
    json_text = M._encode_json(tbl)
  end

  local dir = Snapshots.paths.tempDirRoot()
  local body_file = dir .. "/snap_post_body_" ..
    string.format("%08x", math.random(0, 0x7FFFFFFF)) .. ".json"
  local f = io.open(body_file, "w")
  if f then
    f:write(json_text)
    f:close()
    -- 0600 the body (best-effort; no-op on hosts without chmod).
    pcall(function() os.execute("/bin/chmod 600 " .. Q .. body_file .. Q) end)
  end

  local hdrs = {}
  for _, h in ipairs(opts.headers or M.browser_headers()) do hdrs[#hdrs + 1] = h end
  hdrs[#hdrs + 1] = CT_JSON

  local res = M.request{
    url             = url,
    method          = "POST",
    headers         = hdrs,
    body_file       = body_file,
    cookie          = opts.cookie,
    follow_redirect = false,
    dump_header     = opts.dump_header,
    out             = opts.out,
    max_time        = opts.max_time,
    runner          = opts.runner,
  }
  res._body_file = body_file
  pcall(os.remove, body_file)   -- belt-and-suspenders: body gone immediately
  return res
end

-- ── build_argv(req) -> cmd | nil, err (busybox-wget console backend) ────────
-- busybox wget has NO -K config and NO cookie jar, so every value goes on argv: single-quote
-- each for the console /bin/sh (busybox ash) with '\'' escaping and reject [\r\n]. Body via
-- --post-file (never argv); the cookie via --header "Cookie:".
function M.build_argv(req)
  local okv, verr = validate_scalars(req)
  if not okv then return nil, verr end

  local function shq(v)
    v = tostring(v)
    if v:find("[\r\n]") then return nil, "value contains newline" end
    return "'" .. v:gsub("'", [['\'']]) .. "'"
  end

  local parts = { "wget", "-q", "-S" }   -- -S dumps response headers to stderr
  local rejected

  local function push(flag, value)
    if rejected then return end
    local sv, serr = shq(value)
    if sv == nil then rejected = serr; return end
    if flag then parts[#parts + 1] = flag end
    parts[#parts + 1] = sv
  end

  if req.out then push("-O", req.out) end
  for _, h in ipairs(req.headers or {}) do push("--header", h) end
  if req.cookie then push("--header", "Cookie: PHPSESSID=" .. req.cookie) end
  if req.body_file then push("--post-file", req.body_file) end   -- body OFF argv (TRAN-05)

  local mt = math.floor(tonumber(req.max_time) or 30)
  parts[#parts + 1] = "-T"
  parts[#parts + 1] = tostring(mt)

  push(nil, req.url)
  if rejected then return nil, rejected end

  local cmd = table.concat(parts, " ")
  if req.dump_header then
    local h, herr = shq(req.dump_header)
    if h == nil then return nil, herr end
    cmd = cmd .. " 2>" .. h   -- -S headers (stderr) -> hdr file; parse_response reads it
  end
  return cmd
end

return M
