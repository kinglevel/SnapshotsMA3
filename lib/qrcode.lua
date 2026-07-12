-- qrcode.lua — pure-Lua QR encoder (byte mode, auto-version, EC-M default).
-- Returns a boolean module matrix. NO MA3 globals, no rendering. Lua 5.4+ (bitwise + //).
-- Used by the donation overlay to render a scannable QR as a grid of UI cells; matrix output
-- is verified bit-for-bit against a reference QR generator for a fixed input.

Snapshots = Snapshots or {}
local M = {}
Snapshots.qrcode = M

-- ── GF(256), primitive 0x11D ────────────────────────────────────────────────
local EXP, LOG = {}, {}
do
  local x = 1
  for i = 0, 254 do
    EXP[i] = x
    LOG[x] = i
    x = x << 1
    if x >= 256 then x = x ~ 0x11D end
  end
  for i = 255, 511 do EXP[i] = EXP[i - 255] end
end
local function gmul(a, b)
  if a == 0 or b == 0 then return 0 end
  return EXP[LOG[a] + LOG[b]]
end

local function rs_generator(n)
  local g = { 1 }
  for i = 0, n - 1 do
    -- multiply g by (x + EXP[i])
    local ng = {}
    for j = 1, #g + 1 do ng[j] = 0 end
    for j = 1, #g do
      ng[j]     = ng[j] ~ g[j]                    -- x term (leading/high-order)
      ng[j + 1] = (ng[j + 1] or 0) ~ gmul(g[j], EXP[i]) -- constant term
    end
    g = ng
  end
  return g -- length n+1, g[1] = leading coeff (1)
end

local function rs_encode(data, n)
  local gen = rs_generator(n)
  local res = {}
  for i = 1, #data do res[i] = data[i] end
  for i = 1, n do res[#data + i] = 0 end
  for i = 1, #data do
    local coef = res[i]
    if coef ~= 0 then
      for j = 2, #gen do
        res[i + j - 1] = res[i + j - 1] ~ gmul(gen[j], coef)
      end
    end
  end
  local ec = {}
  for i = 1, n do ec[i] = res[#data + i] end
  return ec
end

-- ── EC-M block/capacity tables (versions 1..10) ─────────────────────────────
-- {total_data_codewords, ec_per_block, {blocks: {count, data_per_block}, ...}}
local ECM = {
  [1]  = { 16,  10, { { 1, 16 } } },
  [2]  = { 28,  16, { { 1, 28 } } },
  [3]  = { 44,  26, { { 1, 44 } } },
  [4]  = { 64,  18, { { 2, 32 } } },
  [5]  = { 86,  24, { { 2, 43 } } },
  [6]  = { 108, 16, { { 4, 27 } } },
  [7]  = { 124, 18, { { 4, 31 } } },
  [8]  = { 154, 22, { { 2, 38 }, { 2, 39 } } },
  [9]  = { 182, 22, { { 3, 36 }, { 2, 37 } } },
  [10] = { 216, 26, { { 4, 43 }, { 1, 44 } } },
}

-- Alignment pattern center positions per version (1..10).
local ALIGN = {
  [1] = {}, [2] = { 6, 18 }, [3] = { 6, 22 }, [4] = { 6, 26 }, [5] = { 6, 30 },
  [6] = { 6, 34 }, [7] = { 6, 22, 38 }, [8] = { 6, 24, 42 }, [9] = { 6, 26, 46 },
  [10] = { 6, 28, 50 },
}

-- byte-mode capacity (chars) per EC-M version — for auto-select
local function byte_capacity(v)
  local total_data = ECM[v][1]
  local count_bits = (v <= 9) and 8 or 16
  -- data bits available = total_data*8; minus 4 (mode) minus count_bits
  return (total_data * 8 - 4 - count_bits) // 8
end

-- ── bit buffer ──────────────────────────────────────────────────────────────
local function new_bits() return { n = 0, bytes = {} } end
local function put_bit(b, v)
  local byteIdx = (b.n // 8) + 1
  local bit = 7 - (b.n % 8)
  b.bytes[byteIdx] = (b.bytes[byteIdx] or 0) | ((v & 1) << bit)
  b.n = b.n + 1
end
local function put_bits(b, val, len)
  for i = len - 1, 0, -1 do put_bit(b, (val >> i) & 1) end
end

-- ── encode text → codewords for the chosen version ──────────────────────────
local function build_codewords(text, version)
  local total_data = ECM[version][1]
  local count_bits = (version <= 9) and 8 or 16
  local b = new_bits()
  put_bits(b, 0x4, 4)             -- byte mode
  put_bits(b, #text, count_bits)  -- char count
  for i = 1, #text do put_bits(b, text:byte(i), 8) end
  -- terminator (up to 4 zero bits)
  local cap_bits = total_data * 8
  local term = math.min(4, cap_bits - b.n)
  for _ = 1, term do put_bit(b, 0) end
  -- pad to byte boundary
  while b.n % 8 ~= 0 do put_bit(b, 0) end
  -- codewords so far
  local cw = {}
  for i = 1, b.n // 8 do cw[i] = b.bytes[i] or 0 end
  -- pad bytes
  local pad = { 0xEC, 0x11 }
  local pi = 1
  while #cw < total_data do
    cw[#cw + 1] = pad[pi]
    pi = 3 - pi
  end
  return cw
end

-- ── interleave data + EC codewords across blocks ────────────────────────────
local function interleave(cw, version)
  local ecPer = ECM[version][2]
  local groups = ECM[version][3]
  local blocks = {}     -- each: {data={...}, ec={...}}
  local idx = 1
  for _, grp in ipairs(groups) do
    local nblk, dper = grp[1], grp[2]
    for _ = 1, nblk do
      local d = {}
      for j = 1, dper do d[j] = cw[idx]; idx = idx + 1 end
      blocks[#blocks + 1] = { data = d, ec = rs_encode(d, ecPer) }
    end
  end
  local out = {}
  -- interleave data codewords
  local maxData = 0
  for _, blk in ipairs(blocks) do maxData = math.max(maxData, #blk.data) end
  for i = 1, maxData do
    for _, blk in ipairs(blocks) do
      if blk.data[i] then out[#out + 1] = blk.data[i] end
    end
  end
  -- interleave EC codewords
  for i = 1, ecPer do
    for _, blk in ipairs(blocks) do
      out[#out + 1] = blk.ec[i]
    end
  end
  return out
end

-- ── matrix helpers ──────────────────────────────────────────────────────────
local function make_matrix(n)
  local m, reserved = {}, {}
  for r = 1, n do
    m[r], reserved[r] = {}, {}
    for c = 1, n do m[r][c] = false; reserved[r][c] = false end
  end
  return m, reserved
end

local function place_finder(m, reserved, n, top, left)
  for r = -1, 7 do
    for c = -1, 7 do
      local rr, cc = top + r, left + c
      if rr >= 0 and rr < n and cc >= 0 and cc < n then
        local dark = (r >= 0 and r <= 6 and (c == 0 or c == 6))
            or (c >= 0 and c <= 6 and (r == 0 or r == 6))
            or (r >= 2 and r <= 4 and c >= 2 and c <= 4)
        m[rr + 1][cc + 1] = dark
        reserved[rr + 1][cc + 1] = true
      end
    end
  end
end

local function place_alignment(m, reserved, n, version)
  local pos = ALIGN[version]
  local last = pos[#pos] or 0   -- max alignment coord = the finder-adjacent one to skip
  for _, r in ipairs(pos) do
    for _, c in ipairs(pos) do
      local skip = (r == 6 and c == 6) or (r == 6 and c == last) or (r == last and c == 6)
      if not skip then
        for dr = -2, 2 do
          for dc = -2, 2 do
            local dark = (math.abs(dr) == 2 or math.abs(dc) == 2 or (dr == 0 and dc == 0))
            m[r + dr + 1][c + dc + 1] = dark
            reserved[r + dr + 1][c + dc + 1] = true
          end
        end
      end
    end
  end
end

-- BCH(15,5) format info for (EC level bits .. mask)
local function format_bits(ec_level_bits, mask)
  local data5 = (ec_level_bits << 3) | mask
  local d = data5 << 10
  for i = 14, 10, -1 do
    if (d >> i) & 1 == 1 then d = d ~ (0x537 << (i - 10)) end
  end
  local bits = (data5 << 10) | d
  return bits ~ 0x5412
end

-- BCH(18,6) version info (v>=7)
local function version_bits(version)
  local d = version << 12
  for i = 17, 12, -1 do
    if (d >> i) & 1 == 1 then d = d ~ (0x1F25 << (i - 12)) end
  end
  return (version << 12) | d
end

local function reserve_format(reserved, n)
  for i = 0, 8 do
    reserved[9][i + 1] = true      -- row 8
    reserved[i + 1][9] = true      -- col 8
  end
  for i = 0, 7 do
    reserved[9][n - i] = true      -- row 8 right
    reserved[n - i][9] = true      -- col 8 bottom
  end
end

-- Format info placement — mirrors ISO/IEC 18004 §7.9 (segno add_format_info).
-- fi bit0 = LSB, bit14 = MSB. Two copies; timing row/col (index 6) skipped via offsets.
local function place_format(m, n, ec_level_bits, mask)
  local fi = format_bits(ec_level_bits, mask)
  local voff, hoff = 0, 0
  for i = 0, 7 do
    local vbit = (fi >> i) & 1              -- LSB side
    local hbit = (fi >> (14 - i)) & 1       -- MSB side
    if i == 6 then voff = 1; hoff = 1 end   -- step over the timing line
    m[(i + voff) + 1][8 + 1]     = vbit == 1   -- vertical, upper-left (col 8)
    m[8 + 1][(i + hoff) + 1]     = hbit == 1   -- horizontal, upper-left (row 8)
    m[8 + 1][(n - 1 - i) + 1]    = vbit == 1   -- horizontal, upper-right (row 8)
    m[(n - 1 - i) + 1][8 + 1]    = hbit == 1   -- vertical, bottom-left (col 8)
  end
  m[(n - 8) + 1][8 + 1] = true               -- dark module
end

local function place_version(m, reserved, n, version)
  if version < 7 then return end
  local bits = version_bits(version)
  for i = 0, 17 do
    local b = ((bits >> i) & 1) == 1
    local r = i // 3
    local c = i % 3
    -- bottom-left block
    m[n - 11 + c + 1][r + 1] = b
    reserved[n - 11 + c + 1][r + 1] = true
    -- top-right block
    m[r + 1][n - 11 + c + 1] = b
    reserved[r + 1][n - 11 + c + 1] = true
  end
end

local function mask_fn(mask, r, c) -- r,c 0-based
  if mask == 0 then return (r + c) % 2 == 0
  elseif mask == 1 then return r % 2 == 0
  elseif mask == 2 then return c % 3 == 0
  elseif mask == 3 then return (r + c) % 3 == 0
  elseif mask == 4 then return ((r // 2) + (c // 3)) % 2 == 0
  elseif mask == 5 then return (r * c) % 2 + (r * c) % 3 == 0
  elseif mask == 6 then return ((r * c) % 2 + (r * c) % 3) % 2 == 0
  else return ((r + c) % 2 + (r * c) % 3) % 2 == 0 end
end

local function penalty(m, n)
  local score = 0
  -- rule 1: runs >=5 in rows and cols
  for r = 1, n do
    local run, prev = 1, m[r][1]
    for c = 2, n do
      if m[r][c] == prev then run = run + 1 else
        if run >= 5 then score = score + 3 + (run - 5) end
        run = 1; prev = m[r][c]
      end
    end
    if run >= 5 then score = score + 3 + (run - 5) end
  end
  for c = 1, n do
    local run, prev = 1, m[1][c]
    for r = 2, n do
      if m[r][c] == prev then run = run + 1 else
        if run >= 5 then score = score + 3 + (run - 5) end
        run = 1; prev = m[r][c]
      end
    end
    if run >= 5 then score = score + 3 + (run - 5) end
  end
  -- rule 2: 2x2 blocks
  for r = 1, n - 1 do
    for c = 1, n - 1 do
      local v = m[r][c]
      if m[r][c + 1] == v and m[r + 1][c] == v and m[r + 1][c + 1] == v then
        score = score + 3
      end
    end
  end
  -- rule 3: finder-like patterns 1011101 0000 and 0000 1011101
  local pat1 = { true, false, true, true, true, false, true, false, false, false, false }
  local pat2 = { false, false, false, false, true, false, true, true, true, false, true }
  local function match_at(get, i)
    local a, b = true, true
    for k = 1, 11 do
      if get(i + k - 1) ~= pat1[k] then a = false end
      if get(i + k - 1) ~= pat2[k] then b = false end
    end
    return a or b
  end
  for r = 1, n do
    for c = 1, n - 10 do
      if match_at(function(x) return m[r][x] end, c) then score = score + 40 end
    end
  end
  for c = 1, n do
    for r = 1, n - 10 do
      if match_at(function(x) return m[x][c] end, r) then score = score + 40 end
    end
  end
  -- rule 4: dark proportion
  local dark = 0
  for r = 1, n do for c = 1, n do if m[r][c] then dark = dark + 1 end end end
  local pct = (dark * 100) // (n * n)
  local prev5 = (pct // 5) * 5
  local dev = math.min(math.abs(prev5 - 50), math.abs(prev5 + 5 - 50))
  score = score + (dev // 5) * 10
  return score
end

-- ── main encode ─────────────────────────────────────────────────────────────
-- opts.version = "auto" | number ; opts.mask = "auto" | 0..7 ; ec fixed M
function M.encode(text, opts)
  opts = opts or {}
  -- choose version
  local version = opts.version
  if version == nil or version == "auto" then
    version = nil
    for v = 1, 10 do
      if #text <= byte_capacity(v) then version = v; break end
    end
    assert(version, "text too long for versions 1..10 (byte/EC-M)")
  end
  local n = version * 4 + 17

  local cw = build_codewords(text, version)
  local final = interleave(cw, version)

  local m, reserved = make_matrix(n)
  place_finder(m, reserved, n, 0, 0)
  place_finder(m, reserved, n, 0, n - 7)
  place_finder(m, reserved, n, n - 7, 0)
  -- timing patterns
  for i = 8, n - 9 do
    local dark = (i % 2 == 0)
    if not reserved[7][i + 1] then m[7][i + 1] = dark; reserved[7][i + 1] = true end
    if not reserved[i + 1][7] then m[i + 1][7] = dark; reserved[i + 1][7] = true end
  end
  place_alignment(m, reserved, n, version)
  -- dark module
  m[(4 * version + 9) + 1][9] = true
  reserved[(4 * version + 9) + 1][9] = true
  reserve_format(reserved, n)
  place_version(m, reserved, n, version)

  -- place data bits in zigzag
  local bitIdx = 0
  local totalBits = #final * 8
  local function next_bit()
    if bitIdx >= totalBits then return false end
    local byte = final[(bitIdx // 8) + 1]
    local b = (byte >> (7 - (bitIdx % 8))) & 1
    bitIdx = bitIdx + 1
    return b == 1
  end
  local col = n - 1
  local upward = true
  while col >= 0 do
    if col == 6 then col = 5 end -- skip timing column
    for i = 0, n - 1 do
      local r = upward and (n - 1 - i) or i
      for _, c in ipairs({ col, col - 1 }) do
        if not reserved[r + 1][c + 1] then
          m[r + 1][c + 1] = next_bit()
        end
      end
    end
    upward = not upward
    col = col - 2
  end

  -- choose mask
  local ec_level_bits = 0 -- M = 00
  local bestMask, bestScore
  if type(opts.mask) == "number" then
    bestMask = opts.mask
  else
    for mask = 0, 7 do
      -- apply mask to a copy
      local mm = {}
      for r = 1, n do mm[r] = {}; for c = 1, n do mm[r][c] = m[r][c] end end
      for r = 0, n - 1 do
        for c = 0, n - 1 do
          if not reserved[r + 1][c + 1] and mask_fn(mask, r, c) then
            mm[r + 1][c + 1] = not mm[r + 1][c + 1]
          end
        end
      end
      place_format(mm, n, ec_level_bits, mask)
      local s = penalty(mm, n)
      if bestScore == nil or s < bestScore then bestScore = s; bestMask = mask end
    end
  end

  -- apply chosen mask + format
  for r = 0, n - 1 do
    for c = 0, n - 1 do
      if not reserved[r + 1][c + 1] and mask_fn(bestMask, r, c) then
        m[r + 1][c + 1] = not m[r + 1][c + 1]
      end
    end
  end
  place_format(m, n, ec_level_bits, bestMask)

  return { matrix = m, size = n, version = version, mask = bestMask, ec = "M" }
end

return M
