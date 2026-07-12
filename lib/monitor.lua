-- lib/monitor.lua (Snapshots.monitor) — bounded ring buffer backing the UI-03
-- System Monitor strip: the last N notify display-lines (arg echoes, skip reports).
-- Centralizing the cap here keeps the console render dumb and the boundary clean.
-- PURE module — touches no MA3 global (boundary policy D-06). Holds plain strings
-- only; NEVER load()/loadstring() a stored line (T-09-03 — display data only).
-- Ordering: buffer stores oldest->newest; list() returns the SAME order; the render
-- paints top->bottom so the NEWEST line sits at the BOTTOM of the strip.
Snapshots = Snapshots or {}   -- idempotent bootstrap (NEVER `= {}` — wipes siblings)
local Monitor = {}

Monitor.CAP = 8               -- hard cap; drops oldest on overflow (T-09-04 DoS guard)

local buffer = {}             -- module-scoped ring, oldest->newest

-- push(msg): append one display line, coerce non-strings (nil -> "" so there is
-- never a nil hole in the array), drop the oldest while over CAP, return #buffer.
function Monitor.push(msg)
  buffer[#buffer + 1] = tostring(msg == nil and "" or msg)
  while #buffer > Monitor.CAP do table.remove(buffer, 1) end
  return #buffer
end

-- list(): return a COPY oldest->newest so a render caller can mutate the result
-- without corrupting or leaking the live buffer (T-09-05).
function Monitor.list()
  local out = {}
  for i = 1, #buffer do out[i] = buffer[i] end
  return out
end

-- clear(): empty the buffer (rebinds a fresh table; the two closures above read
-- `buffer` as an upvalue, so both see the new empty table).
function Monitor.clear()
  buffer = {}
end

Snapshots.monitor = Monitor   -- attach under the namespace key
return Monitor                -- RETURN THE TABLE (tests dofile it for this value)
