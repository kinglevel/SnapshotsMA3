Snapshots = Snapshots or {}   -- idempotent (sibling load order not guaranteed — Pitfall 4)
Snapshots.version = {
  STRING = "2.0.0.0",         -- shown in the sysmon proof-of-life (ver() reads .STRING)
  MAJOR = 2, MINOR = 0, PATCH = 0, BUILD = 0,
}
return function() end   -- no-op: silences the harmless "expecting a 'main' function" ComponentLua warning (Pitfall 6)
