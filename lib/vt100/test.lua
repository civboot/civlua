METATY_CHECK = true

local M = require'vt100'
local T = require'civtest'
local assertEq = T.assertEq

T.test('literal', function()
  local l = M.literal
  assertEq('a',  l'a')
  assertEq('\n', l'return')
  assertEq(nil,  l'invalid')
end)

T.test('keyError', function()
  local ke = M.keyError
  assertEq(nil, ke'a')
  assertEq(nil, ke'esc')
  assertEq(nil, ke'^a')
  assertEq(nil, ke'😜')
  assertEq('invalid key: "escape"', ke'escape')
  assertEq([[key "\8" not a printable character]], ke'\x08')
end)

T.test('keynice', function()
  local key, b = M.key, string.byte
  assertEq('a',      key(b'a'))
  assertEq('^a',     key(1))
  assertEq('tab',    key(9))
  assertEq('^j',     key(10))
  assertEq('return', key(13))
  assertEq('space',  key(32))
  assertEq('^z',     key(26))
end)
