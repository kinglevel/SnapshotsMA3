-- lib/paths.lua (Snapshots.paths) — MA3-globals shim + multiplatform temp-dir lifecycle.
--
-- The SINGLE shim point for the MA3 globals the HTTP POST path needs (GetPath / HostOS /
-- Enums). http.lua NEVER touches those globals directly — it calls Snapshots.paths.*
-- instead. Every MA3 global here is pcall-wrapped so the module runs on host Lua 5.4+
-- outside MA3 (tests/helpers.lua leaves _G.HostOS/_G.GetPath/_G.Enums undefined → the
-- pcall degrades to the host fallback rather than crashing). NEVER called at module load.
--
-- Trimmed to the POST-path helpers (tempDirRoot / hostOS / join / makeTempDir / removeDir).
-- Any cache / downloads / user-fixture helpers are dropped (Snapshots stores in a GlobalVar,
-- not on disk).
--
-- TRAN-01 guard: this file NEVER shells out and NEVER names the HTTPS tool. Both the
-- tool-name decision AND the process invocation live only in lib/http.lua (http.backend()
-- reads the raw host label via paths.hostOS()).

Snapshots = Snapshots or {}   -- idempotent bootstrap (NEVER `= {}` — wipes siblings)
local M = {}
Snapshots.paths = M

-- ── tempDirRoot() — system temp dir absolute path ─────────────────────────
-- Inside MA3:  GetPath(Enums.PathType.Temp) -> .../gma3_X.Y/onpc/temp
-- Outside MA3: $TMPDIR (Mac/Linux) or $TEMP (Windows) or "/tmp"
function M.tempDirRoot()
  local ok, p = pcall(function() return GetPath(Enums.PathType.Temp) end)
  if ok and type(p) == "string" and p ~= "" then return p end
  return os.getenv("TMPDIR") or os.getenv("TEMP") or "/tmp"
end

-- ── hostOS() — pcall-wrapped HostOS() ─────────────────────────────────────
-- Returns "Mac" | "Windows" | console-label | nil (nil when HostOS raises). http.backend()
-- reads this to pick curl (Mac/Windows) vs busybox wget (console).
function M.hostOS()
  local ok, h = pcall(function() return HostOS() end)
  if ok then return h end
  return nil
end

-- ── join(...) — concatenate path parts with the platform separator ────────
-- Backslash only when hostOS() is "Win" or "Windows"; forward slash otherwise (Mac,
-- console — whose exact label is unconfirmed — default to forward slash).
function M.join(...)
  local parts = {...}
  local sep = "/"
  local h = M.hostOS()
  if h == "Win" or h == "Windows" then sep = "\\" end
  return table.concat(parts, sep)
end

-- ── makeTempDir() — allocate a fresh per-run private directory ─────────────
-- Format: <tempRoot>/snap-<pid>-<rand>/
-- Returns (path, nil) on success, (nil, errmsg) on failure. One collision retry.
function M.makeTempDir()
  local lfs = require("lfs")
  local root = M.tempDirRoot()
  local pid = os.getenv("PPID") or "0"
  local rand = string.format("%08x", math.random(0, 0x7FFFFFFF))
  local dir = M.join(root, "snap-" .. pid .. "-" .. rand)
  local ok, err = lfs.mkdir(dir)
  if not ok then
    -- One retry with a fresh suffix in case of (rare) collision.
    rand = string.format("%08x", math.random(0, 0x7FFFFFFF))
    dir  = M.join(root, "snap-" .. pid .. "-" .. rand)
    ok, err = lfs.mkdir(dir)
    if not ok then return nil, "mkdir " .. dir .. ": " .. tostring(err) end
  end
  return dir
end

-- ── removeDir(path) — recursive removal, scoped to tempDirRoot() ──────────
-- Refuses to remove anything not under tempDirRoot() — belt-and-suspenders against an
-- accidental rm of show files / library / cwd / "/" (HTTP per-request cleanup).
function M.removeDir(path)
  local lfs = require("lfs")
  local root = M.tempDirRoot()
  if type(path) ~= "string" or path == "" then
    return nil, "removeDir: empty/invalid path"
  end
  if path:sub(1, #root) ~= root then
    return nil, "refuse to remove outside temp root: " .. path
  end
  -- If the directory doesn't exist, treat as no-op success (idempotent cleanup).
  local mode = lfs.attributes(path, "mode")
  if mode == nil then return true end
  if mode ~= "directory" then return nil, "removeDir: not a directory: " .. path end

  for entry in lfs.dir(path) do
    if entry ~= "." and entry ~= ".." then
      local full = M.join(path, entry)
      local emode = lfs.attributes(full, "mode")
      if emode == "directory" then
        local ok, err = M.removeDir(full)
        if not ok then return nil, err end
      else
        os.remove(full)
      end
    end
  end
  return lfs.rmdir(path)
end

return M
