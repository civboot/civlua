
local pkg = require'pkglib'
local mty = require'metaty'
local ds = require'ds'
local heap = require'ds.heap'

local char, byte = string.char, string.byte
local push = table.insert

local M = mty.docTy({}, [[smol: data compression algorithms to make data smaller.]])

local B8 = {
  0x01, 0x03, 0x07, 0x0F,
  0x1F, 0x3F, 0x7F, 0xFF,
}; M.BITMASK8 = B8

function M.bitsmax(bits)
  assert(bits <= 32); return (1 << bits) - 1
end

---------------------
-- File Codes
M.FileCodes = mty.doc[[FileCodes(file): file as 8bit codes.]]
(mty.record'FileCodes')
  :field('file', 'userdata')
:new(function(ty_, file) return mty.new(ty_, {file=file}) end)
M.FileCodes.reset = function(fc) fc.file:seek'set' end
M.FileCodes.__call = function(fc)
  local c = fc.file:read(1)
  return c and byte(c) or nil
end

---------------------
-- Bits
M.WriteBits = mty.doc[[Write bits as big-endian.
Compression is all about making things as small as possible
and it don't get smaller than bits.

See tests for examples.
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

return M
