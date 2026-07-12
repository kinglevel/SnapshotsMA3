-- tests/test_qrcode.lua — pure QR encoder (Snapshots.qrcode).
-- Proves the matrix shape + deterministic sizing the donate overlay renders, and that the
-- module is PURE (no MA3-globals reach at load or in encode()) — the harness leaves Cmd/Obj/
-- Root/GlobalVars undefined, so any accidental reach would crash this dofile. No os.exit here.
local h = dofile((debug.getinfo(1,"S").source:sub(2):match("(.*/)") or "./") .. "helpers.lua")

h.run("qrcode loads pure (no MA3 globals) + attaches to namespace", function()
  local M = h.loadModule("qrcode.lua")
  h.assertTrue(type(M) == "table", "returns a module table")
  h.assertTrue(type(M.encode) == "function", "exposes encode()")
  h.assertTrue(_G.Snapshots.qrcode == M, "attaches Snapshots.qrcode")
end)

h.run("qrcode.encode returns numeric size + boolean matrix (dark = true)", function()
  local M = h.loadModule("qrcode.lua")
  local enc = M.encode("http://community.smidn.com/donate", { mask = 6 })
  h.assertTrue(type(enc) == "table", "encode returns a table")
  h.assertTrue(type(enc.size) == "number", "size is numeric")
  h.assertTrue(enc.size == 4 * enc.version + 17, "size == 4*version+17")
  h.assertTrue(type(enc.matrix) == "table", "matrix is a table")
  -- every cell in the module grid is a boolean (true = dark module)
  local sawDark = false
  for r = 1, enc.size do
    for c = 1, enc.size do
      local v = enc.matrix[r][c]
      h.assertTrue(v == true or v == false, "matrix cell is boolean")
      if v == true then sawDark = true end
    end
  end
  h.assertTrue(sawDark, "at least one dark module present")
  -- mask was pinned → echoed back
  h.assertEq(enc.mask, 6, "requested mask honored")
end)

h.run("qrcode.encode is deterministic in version selection (short string -> v1/size 21)", function()
  local M = h.loadModule("qrcode.lua")
  local enc = M.encode("HELLO", { mask = 0 })
  h.assertEq(enc.version, 1, "5-char byte payload fits version 1")
  h.assertEq(enc.size, 21, "version 1 module grid is 21x21")
end)
