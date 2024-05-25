
local T = require'civtest'
local M = require'lson'
local mty = require'metaty'
local lines = require'lines'

local function testString(encoded, decoded)
  local de = mty.construct(M.De, {l=1, c=1, line=encoded})
  T.assertEq(decoded, M.pString(de))
end
T.test('string', function()
  testString([["example string"]],     [[example string]])
  testString([["example \"string\""]], [[example "string"]])
end)

local function test(t, enc, expectEncoding)
  enc = enc or M.Encoder:pretty{}
  print('!! encoding')
  enc(t)
  local encoded = table.concat(enc)
  print('!! encoded', encoded)
  if expectEncoding then
    T.assertEq(expectEncoding, encoded)
  end
  local de = M.De(lines(encoded))
  local decoded = de()
  T.assertEq(t, decoded)
  return enc, de
end

T.test('round', function()
  test({1, 2, 3}, nil, '[\n  1, 2, 3\n]')
end)
