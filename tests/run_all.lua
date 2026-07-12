-- tests/run_all.lua — authoritative off-console gate (D-07).
-- Self-contained driver: dofiles the shared-singleton helpers, pcall-loads each
-- test file, and owns the single process-exit for the whole suite (Pitfall 8).
local HERE = (debug.getinfo(1,"S").source:sub(2):match("(.*/)") or "./")
local helpers = dofile(HERE .. "helpers.lua")
local files = { "test_boundary.lua", "test_json.lua",
                "test_num.lua", "test_monitor.lua", "test_schema.lua", "test_args.lua",
                "test_model.lua", "test_fade.lua", "test_breakdown.lua",
                "test_store.lua", "test_ma3.lua", "test_dispatch.lua",
                "test_manager.lua", "test_assign.lua",
                "test_qrcode.lua", "test_search.lua" }
for _, f in ipairs(files) do
  local probe = io.open(HERE .. f, "r")
  if not probe then print("SKIP (absent) " .. f)
  else probe:close(); print("== " .. f)
    local ok, err = pcall(dofile, HERE .. f)
    if not ok then print("FAIL (load) "..f..": "..tostring(err)); helpers.failed = helpers.failed + 1 end
  end
end
print("==")
os.exit(helpers.summary() and 0 or 1)   -- the ONLY os.exit in the suite
