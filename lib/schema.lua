-- lib/schema.lua (Snapshots.schema) — the object-ref shape the model dedups on.
-- OBJ-01 ref {guid, addr, label, type, datapool} (datapool per SP3/D-08), the
-- TYPES enum, new_ref (construct + validate), and key (GUID-first identity with
-- an "@"..addr fallback so executors — which have no usable GUID, SP3 — are
-- addr-keyed and disjoint from guid-keyed objects).
-- PURE module — schema only HOLDS guids; reading them from MA3 is Phase 5.
-- Touches no MA3 global (boundary policy D-06).
Snapshots = Snapshots or {}   -- idempotent bootstrap (NEVER `= {}` — wipes siblings)
local Schema = {}

-- The five object classes a snapshot slot can reference.
Schema.TYPES = { executor=true, sequence=true, preset=true, group=true, master=true }

-- Build a validated object-ref. Requires a type in TYPES and at least one of
-- guid|addr (executors legitimately have guid nil and are keyed by addr).
function Schema.new_ref(t)
  assert(Schema.TYPES[t.type], "schema.new_ref: bad type "..tostring(t.type))
  assert(t.guid or t.addr,     "schema.new_ref: need guid or addr")
  return {
    guid     = t.guid,      -- string hex OR nil (executors have no usable GUID — SP3)
    addr     = t.addr,      -- "1.201" | "Group 2" | "Master 2.1"
    label    = t.label,     -- display cache, rebuilt on load (D-08)
    type     = t.type,      -- enum member
    datapool = t.datapool,  -- opaque in Phase 3 (D-15): index or GUID, not interpreted here
  }
end

-- Identity primitive: the guid when present, else "@"..addr (executor fallback).
function Schema.key(ref)
  return ref.guid or ("@"..tostring(ref.addr))
end

Snapshots.schema = Schema   -- attach under the namespace key
return Schema               -- RETURN THE TABLE (tests dofile it for this value)
