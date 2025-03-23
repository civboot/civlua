METATY_CHECK = true

local M = require'vt100'
local T = require'civtest'.Test()
local mty = require'metaty'
local fmt = require'fmt'
local ac = require'asciicolor'

local assertHasAsciiColors = function(c)
  for code, name in pairs(ac.Color) do
    fmt.assertf(c[name], 'missing %q', name)
  end
end
T.color = function()
  assertHasAsciiColors(M.FgColor)
  assertHasAsciiColors(M.BgColor)
end

T.literal = function()
  local l = M.literal
  T.eq('a',  l'a')
  T.eq('\n', l'return')
  T.eq(nil,  l'invalid')
end

T.keyError = function()
  local ke = M.keyError
  T.eq(nil, ke'a')
  T.eq(nil, ke'esc')
  T.eq(nil, ke'^a')
  T.eq(nil, ke'😜')
  T.eq('invalid key: "escape"', ke'escape')
  T.eq([[key "\8" not a printable character]], ke'\x08')
end

T.keynice = function()
  local key, b = M.key, string.byte
  T.eq('a',      key(b'a'))
  T.eq('^a',     key(1))
  T.eq('tab',    key(9))
  T.eq('^j',     key(10))
  T.eq('return', key(13))
  T.eq('space',  key(32))
  T.eq('^z',     key(26))
end
