
local char, byte = string.char, string.byte
local co         = coroutine
local mty = require'metaty'

local M = mty.docTy({}, [[smol: data compression algorithms to make data smaller.]])

local B8 = {
  0x01, 0x03, 0x07, 0x0F,
  0x1F, 0x3F, 0x7F, 0xFF,
}; M.BITMASK8 = B8

function M.bitsmax(bits) assert(bits <= 32); return (1 << bits) - 1 end

---------------------
-- Bits: writing and reading packed bits to/from a file-like object.
-- Compression is all about making things as small as possible, so there is a
-- very strong need to pack bits together. This makes it easy.
M.WriteBits = mty.doc[[Write bits as big-endian.
Example:
  wb = WriteBits{file=io.open(path, 'wb'), bits=12}
  wb(1055)
  wb.file:flush(); wb.file:close()
]]
(mty.record'WriteBits')
  :field('file', 'userdata')
  :fieldMaybe('bits', 'number')
  :field('_data',     'number', 0) -- max 0xFF
  :field('_dataBits', 'number', 0) -- 1-8

M.WriteBits.__call = function(wb, n, bits)
  bits = assert(bits or wb.bits, 'no bits'); assert(bits > 0)
  local data, dataBits = wb._data or 0, wb._dataBits
  while bits > 0 do
    local mbits = math.min(8 - dataBits, bits) -- minBits
    assert(mbits > 0, mbits)
    data = (data << mbits) | ((n >> (bits - mbits)) & B8[mbits])
    dataBits, bits = dataBits + mbits, bits - mbits
    if dataBits >= 8 then
      assert(dataBits == 8, dataBits)
      assert(data <= 0xFF, data)
      wb.file:write(char(data))
      data, dataBits = 0, 0
    else break end
  end
  wb._data, wb._dataBits = data, dataBits
end

M.WriteBits.finish = mty.doc[[write any leftover data and flush.]]
(function(wb)
  if wb._dataBits > 0 then
    wb.file:write(char(wb._data << (8 - wb._dataBits)))
  end
  wb._data, wb._dataBits = nil, nil
  wb.file:flush()
end)

M.ReadBits = mty.doc[[Read bits as big-endian

  rb = ReadBits{file=io.open(path, 'rb'), bits=12}
  my12bitvalue = rb()
]]
(mty.record'ReadBits')
  :field('file', 'userdata')
  :fieldMaybe('bits', 'number')
  :field('_data',     'number', 0) -- max 0xFF
  :field('_dataBits', 'number', 0) -- 1-8

M.ReadBits.__call = function(rb, bits)
  bits = assert(bits or rb.bits, 'no bits')
  local n, data, dataBits = 0, rb._data, rb._dataBits
  while bits > 0 do
    if dataBits == 0 then
      data, dataBits = rb.file:read(1), 8
      if data then data = byte(data)
      else dataBits = 0; return end
    end
    local mbits = math.min(bits, dataBits) -- minBits
    n = (n << mbits) | ((data >> (dataBits - mbits)) & B8[mbits])
    bits, dataBits = bits - mbits, dataBits - mbits
  end
  rb._data, rb._dataBits = data, dataBits
  return n
end

---------------------
-- LZW
M.lzw = mty.docTy({}, [[
lzw: implementation of Lempel–Ziv–Welch compresion algorithm.
  See README for a full description of the algorithm.
]])

M.lzw.encode = mty.doc[[(file, bits) -> yield code
Example:
  local file = io.open(path, 'rb')
  local enc = coroutine.wrap(lzw.encode)
  for code in enc(file, lzw.MAX16) do -- 0xFFFF=16 bit codes
    ... do something with code like WriteBits
  end
]](function(file, bits)
  local max = M.bitsmax(assert(bits))
  local dict = {}; for b=0,0xFF do dict[char(b)] = b end
  local word, nextCode = '', 0x100
  co.yield()
  while true do
    local c = file:read(1); if not c then break end
    local wordc = word..c
    if dict[wordc] then word = wordc
    else
      co.yield(dict[word])
      dict[wordc] = nextCode; nextCode = nextCode + 1
      word = c
      if nextCode > max then break end
    end
  end
  if nextCode > max then
    while true do
      local c = file:read(1); if not c then break end
      local wordc = word..c
      if dict[wordc] then word = wordc
      else co.yield(dict[word]); word = c end
    end
  end
  if #word > 0 then co.yield(dict[word]) end
end)

M.lzw.decode = mty.doc[[decode(codestream, bits) -> yield string
Example:
  local stream = ReadBits(io.open(path, 'rb'), 16)
  local dec = coroutine.wrap(lzw.decode)
  for str in dec(file, lzw.MAX16) do
    ... do something with str like write to file.
  end
]](function(codes, bits)
  local max, nextCode = M.bitsmax(assert(bits)), 0x100
  local dict = {}; for b=0,0xFF do dict[b] = char(b) end
  co.yield()
  local word = codes() if not word then return end
  word = char(word); co.yield(word)
  for code in codes do
    local entry = dict[code]
    if entry then -- pass, found code
    elseif code == nextCode then -- special case #3 (see README)
      entry = word..word:sub(1,1)
    else mty.errorf('invalid code: 0x%X', code) end
    co.yield(entry)
    dict[nextCode] = word..entry:sub(1,1)
    nextCode = nextCode + 1
    word = entry
    if nextCode > max then break end
  end
  if nextCode > max then
    for code in codes do
      local entry = assert(dict[code])
      co.yield(entry)
    end
  end
end)

---------------------
-- Bin Coding
--

M.bin = mty.docTy({}, [[
Bin Coding: organize most used codes into small-prefix bins
]])

-- See create. table.sort "return true when l should be before r"
local function cmpFreq(l, r) return l[1] > r[1] end

local function sumFreq(freq, li, hi)
  local s = 0; for i=li,hi do s = s + freq[i][1] end
  return s
end

-- recursively sum the quadrants from low-index to hi-index
local function sumQuads(freq, li, hi)
  local mi  = (li + hi) // 2
  local miq = (li + mi) // 2
  if hi - li < 16 then
    return {
      sumFreq(freq, 1, miq),    -- quarter 1
      sumFreq(freq, miq+1, mi), -- quarter 2
      sumFreq(freq, mi+1, hi)   -- half 2
    }
  end
  return {
    sumQuads(freq, 1,     miq), -- quarter 1
    sumQuads(freq, miq+1, mi),  -- quarter 2
    sumFreq(freq, mi+1, hi)     -- half 2
  }
end

M.create = mty.doc[[(encoder, bits) -> bins]]
(function(encoder, bits)
  local max = M.bitsmax(assert(bits))

  local freq = {} -- contains {count, code}, will sort
  for code in encoder do
    local v = freq[code] or {0, code}
    v[1] = v[1] + 1
  end
  table.sort(freq, cmpFreq)
end)

return M
