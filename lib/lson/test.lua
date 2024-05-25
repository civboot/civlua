
local T = require'civtest'
local M = require'lson'
local mty = require'metaty'
local ds  = require'ds'
local lines = require'lines'

local function testString(encoded, decoded)
  local de = mty.construct(M.De, {l=1, c=1, line=encoded})
  T.assertEq(decoded, M.deString(de))
end
T.test('string', function()
  testString([["example string"]],     [[example string]])
  testString([["example \"string\""]], [[example "string"]])
end)

T.test('skipWs', function()
  local de = M.De(lines'  a\n  b')
  de:skipWs(); T.assertEq('a', de.line:sub(de.c,de.c))
  de.c = de.c + 1
  de:skipWs(); T.assertEq('b', de.line:sub(de.c,de.c))
end)

local function test(t, enc, expectEncoding)
  enc = enc or M.Json{}
  enc(t)
  local encoded = table.concat(enc)
  if expectEncoding then
    T.assertEq(expectEncoding, encoded)
  end
  local de = M.De(lines(encoded))
  local decoded = de()
  T.assertEq(t, decoded)
  return enc, de
end

T.test('lax', function()
  T.assertEq({1, 2},   M.decode'[1 2]')
  T.assertEq({a=2, 1}, M.decode'{1:1 "a":2}')
  T.assertErrorPat('1%.4: missing pattern ":"',
    function() M.decode'{1 "a":2}' end)
end)

T.test('bytes', function()
  T.assertEq('abc',     M.decode '|abc|')
  T.assertEq('a\nc',    M.decode '|a\\nc|')
  T.assertEq('a\\nc',   M.decode[[|a\\nc|]])
  T.assertEq('a\\nc |', M.decode[[|a\\nc \||  ]])
end)

T.test('round', function()
  local L = M.Lson
  test({1, 2, 3},      nil,  '[1,2,3]')
  test({1, 2, 3},      L{},  '[1 2 3]')

  test({1, a=2},       nil,  '{"a":2,1:1}')
  test({1, a=2},       L{},  '{|a|:2 1:1}')

  test({1, a={3,4}},   nil,  '{"a":[3,4],1:1}')
  test({1, a={3,4}},   L{},  '{|a|:[3 4] 1:1}')

  test({1, a={b=3,4}}, nil,  '{"a":{"b":3,1:4},1:1}')
  test('abc',          nil,  '"abc"')
  test('abc',          L{},  '|abc|')

  test('hi\n\there',   nil,  '"hi\\n\\there"')
  test('hi\n\there',   L{},  '|hi\\n\there|')

  test('hi\\th|ere',    nil,  [["hi\\th|ere"]])
  test('hi\\th|ere',    L{},  [[|hi\th\|ere|]])

  test('hello "happy bob"', nil,  [["hello \"happy bob\""]])
  test('hello "happy bob"', L{},  [[|hello "happy bob"|]])

  test([[\p \s]],    nil, [["\\p \\s"]])
  test([[\p \s \n]], L{}, [[|\p \s \\n|]])

  test(true,              nil,  'true')
  test(ds.none,           nil,  'null')
  test({[ds.none]=false}, nil, '{null:false}')
end)
