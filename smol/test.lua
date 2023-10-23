
local T = require'civtest'
local mty = require'metaty'
local M = require'smol'
local V = require'smol.verify'
local civix = require'civix'

local push = table.insert
local test, assertEq = T.test, T.assertEq
local b = string.byte

test('util', function()
  assertEq(0xFF,   M.bitsmax(8))
  assertEq(0xFFF,  M.bitsmax(12))
  assertEq(0xFFFF, M.bitsmax(16))
end)

local TF = '.out/test.bits'

-- exp: table of codes. bits: single number or lookup table of bits
local function testbits(exp, bits, str)
  local wb = M.WriteBits{file=io.open(TF, 'wb')}
  local rb = M.ReadBits{file=io.open(TF, 'rb')}
  local bt = bits -- bitTable
  if type(bits) == 'number' then
    bt, wb.bits, rb.bits = nil, bits, bits
  end
  for i, v in ipairs(exp) do wb(v, bt and bt[i]) end
  wb:finish(); wb.file:close()
  assertEq(str, rb.file:read'a')
  rb.file:seek'set'
  local res = {}
  for _ in ipairs(exp) do
    local v = rb(bt and bt[i]); push(res, assert(v))
  end
  assertEq(exp, res)
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
  local e = {}; for _, b12 in ipairs{0x686, 0x90A } do
    push(e,  b12 >> 9       ) -- high
    push(e, (b12 >> 6) & 0x7) -- midhigh
    push(e, (b12 >> 3) & 0x7) -- midlow
    push(e,  b12       & 0x7) -- low
  end
  testbits(e, 3, 'hi\n')
  push(e, 4)
  testbits(e, 3, 'hi\n'..string.char(0x80))
end)

test('lzw', function()
  V.verify('LZW', 12, false, 'abbbaba', M.lzw.encode, M.lzw.decode)
  V.verify('LZW',  9, false, 'abbbaba', M.lzw.encode, M.lzw.decode)

  -- V.verify('LZW', 12, true, '.out/enwik8_1MiB', M.lzw.encode, M.lzw.decode)
  -- V.verify('LZW', 16, true, '.out/enwik8_1MiB', M.lzw.encode, M.lzw.decode)
  -- print('EXITING')
  -- os.exit(1)
end)

local function sortHuff(h)
  table.sort(h, function(p, c)
    if p.bits > c.bits then return false end
    return p.huff < c.huff
  end)
  return h
end

local function istring(s)
  local i = 0; return function()
    i = i + 1; if i > #s then return end
    return b(s:sub(i,i))
  end
end

test('huff', function()
  local c = M.huff.codes(
    istring'this is to test huffman encoding.')
  sortHuff(c)
  mty.pnt('!!!! GOT:', c)

  for i, v in ipairs(c) do
    mty.pntf('%3i,%s,0x%X,%s',
      i, string.char(v.code), v.huff, v.bits)
    -- mty.pntf('%3i,%s', i, string.char(v.code))
  end

  print('EXITING')
  os.exit(1)
end)
