METATY_CHECK = true

local pkg = require'pkglib'
local T = pkg'civtest'
local term = pkg'civix.term'

local function testU8(expect, chrs)
  local c = table.remove(chrs, 1)
  local lenMsk = term.U8MSK[0xF8 & c]; assert(lenMsk, 'lenMsk is nil')
  T.assertEq(#chrs, lenMsk[1] - 1)
  c = term.u8decode(lenMsk, c, chrs)
  T.assertEq(expect, utf8.char(c))
end

-- chrs were gotten from python:
--   print('{'+', '.join('0x%X' % c for c in '🙃'.encode('utf-8'))+'}')
-- Edge case characters are from:
--   https://design215.com/toolbox/ascii-utf8.php
T.test('u8edges', function()
  testU8('\0', {0})
  testU8(' ', {0x20})
  testU8('a', {string.byte('a')})
  testU8('~', {0x7E})

  testU8('¡', {0xC2, 0xA1})
  testU8('ƒ', {0xC6, 0x92})
  testU8('߿', {0xDF, 0xBF})

  testU8('ࠀ', {0xE0, 0xA0, 0x80})
  testU8('ἰ', {0xE1, 0xBC, 0xB0})
  testU8('‡', {0xE2, 0x80, 0xA1})
  testU8('➤', {0xE2, 0x9E, 0xA4})
  testU8('⮝', {0xE2, 0xAE, 0x9D})
  testU8('€', {0xE2, 0x82, 0xAC})
  testU8('�', {0xEF, 0xBF, 0xBD})

  testU8('𒀀',  {0xF0, 0x92, 0x80, 0x80})
  testU8('🙃', {0xF0, 0x9F, 0x99, 0x83})
  testU8('🧿', {0xF0, 0x9F, 0xA7, 0xBF})
end)

