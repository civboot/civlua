
local T = require'civtest'
local M = require'smol'

local push = table.insert
local test, assertEq = T.test, T.assertEq
local b = string.byte

test('util', function()
  assertEq(0xFF,   M.bitsmax(8))
  assertEq(0xFFF,  M.bitsmax(12))
  assertEq(0xFFFF, M.bitsmax(16))
end)

local TF = 'out/test.bits'

-- exp: table of codes. bits: single number or lookup table of bits
local function testbits(exp, bits, str)
  local wb = M.WriteBits{file=io.open(TF, 'wb')}
  local rb = M.ReadBits{file=io.open(TF, 'rb')}
  local bt = bits -- bitTable
  if type(bits) == 'number' then
    bt, wb.bits, rb.bits = nil, bits, bits
  end
  for i, v in ipairs(exp) do wb(v, bt and bt[i]) end
  wb.file:flush(); wb.file:close()
  local res = {}
  while true do
    v = rb(bt and bt[i]); if not v then break end
    push(res, v)
  end
  assertEq(exp, res)
  rb.file:seek'set'; assertEq(str, rb.file:read'a')
  rb.file:close()
end

test('bits', function()
  testbits({b'h', b'i', b'\n'}, 8,            'hi\n')
  testbits({0x6, 0x8, 0x6, 0x9, 0x0, 0xA}, 4, 'hi\n')
  testbits({0x6869, 0x0A0A},              16, 'hi\n\n')
  testbits({0x686,         0x90A},        12, 'hi\n')

  -- 'hi\n' in 2bit values
  local e = {}; for _, b4 in ipairs{0x6, 0x8, 0x6, 0x9, 0x0, 0xA} do
    push(e, b4 >> 2 ) -- 2bit high
    push(e, b4 & 0x3) -- 2bit low
  end
  testbits(e, 2, 'hi\n')

  -- 'hi\n' in 3bit values
  local e = {}; for _, b12 in ipairs{0x686,         0x90A} do
    push(e,  b12 >> 9        ) -- high
    push(e, (b12 >> 6) & 0x7 ) -- midhigh
    push(e, (b12 >> 3) & 0x7 ) -- midlow
    push(e, b12         & 0x7) -- low
  end
  testbits(e, 3, 'hi\n')
end)
