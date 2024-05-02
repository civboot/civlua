local SMOL_LARGE = os.getenv('SMOL_LARGE')

local T      = require'civtest'
local pkg = require'pkglib'
local mty    = require'metaty'
local M      = require'smol'
local lzw    = require'smol.lzw'
local huff   = require'smol.huff'
local lzhuff = require'smol.lzhuff'
local V = require'smol.lzhuff'
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

-- exp = {1, 2, 3}              -- value only with bits
-- exp = {{0x7, 3}, {0x3, 2}, {1, 1}}  -- {values,bits}
local function testbits(exp, str, bits)
  local wb = M.WriteBits{file=io.open(TF, 'wb')}
  local rb = M.ReadBits{file=io.open(TF, 'rb')}
  for i, v in ipairs(exp) do
    if type(v) == 'table' then wb(table.unpack(v))
    else                       wb(v, bits) end
  end
  wb:finish(); wb.file:close()
  if str then assertEq(str, rb.file:read'a') end
  rb.file:seek'set'
  local res, v = {}
  for i, e in ipairs(exp) do
    if type(e) == 'table' then v = {rb(e[2]), e[2]}
    else                       v = rb(bits) end
    push(res, assert(v))
  end
  assertEq(exp, res)
  rb.file:close()
end

test('bits', function()
  testbits({b'h', b'i', b'\n'}           , 'hi\n',   8)
  testbits({0x6, 0x8, 0x6, 0x9, 0x0, 0xA}, 'hi\n',   4)
  testbits({0x6869, 0x0A0A}              , 'hi\n\n', 16)
  testbits({0x686,         0x90A}        , 'hi\n',   12)

  -- 'hi\n' in 2bit values
  local e = {}; for _, b4 in ipairs{0x6, 0x8, 0x6, 0x9, 0x0, 0xA} do
    push(e, b4 >> 2 ) -- 2bit high
    push(e, b4 & 0x3) -- 2bit low
  end
  testbits(e, 'hi\n', 2)

  -- 'hi\n' in 3bit values
  local e = {}; for _, b12 in ipairs{0x686, 0x90A } do
    push(e,  b12 >> 9       ) -- high
    push(e, (b12 >> 6) & 0x7) -- midhigh
    push(e, (b12 >> 3) & 0x7) -- midlow
    push(e,  b12       & 0x7) -- low
  end
  testbits(e, 'hi\n', 3)
  push(e, 4)
  testbits(e, 'hi\n'..string.char(0x80), 3)
  testbits({{2, 2}, 1, 1, 1, {2, 2}, 1, {2, 2}, {0, 2}}, nil, 1)
end)

test('lzw', function()
  V.verify('LZW', 12, false, 'abbbaba',
           lzw.Encoder, lzw.Decoder,
           {watch=true})
  V.verify('LZW',  9, false, 'abbbaba',
           lzw.Encoder, lzw.Decoder,
           {watch=true})

end)

test('huff', function()
  V.verify('Huff', 8, false, 'abbbaba',
           huff.easyEncoder, huff.easyDecoder,
           {finalDecode=string.char})
end)

test('lzhuff', function()
  V.verify('LzHuff', 8, false, 'abbbaba',
           lzhuff.encoder, lzhuff.decoder)
end)

test('large', function()
  if not SMOL_LARGE then
    print('... skipping, set SMOL_LARGE=path/to/file to'
          ..' test a large file')
    return
  end
  -- V.verify('Huff', 8, true, SMOL_LARGE,
  --          huff.easyEncoder, huff.easyDecoder,
  --          {finalDecode=string.char})
  V.verify('LZW', 12, true, SMOL_LARGE,
           lzw.Encoder, lzw.Decoder)
  V.verify('LzHuff', 12, true, SMOL_LARGE,
           lzhuff.encoder, lzhuff.decoder)
  V.verify('LZW', 16, true, SMOL_LARGE,
           lzw.Encoder, lzw.Decoder)
  V.verify('LzHuff', 16, true, SMOL_LARGE,
           lzhuff.encoder, lzhuff.decoder)
  print('exiting after SMOL_LARGE')
  os.exit(1)
end)

