METATY_CHECK = true

local T = require'civtest'
local mty = require'metaty'
local ds = require'ds'
local Writer = require'lines.Writer'
local M = require'asciicolor'
local S = require'asciicolor.style'

local aeq = T.assertEq

-- make sure the codes don't change accidentally
T.test('nochange', function()
  local LETTERS = 'z b w d l r p y h g t c a n s m f'
  local NUM_LET = 17
  local VALID = {}; for c in LETTERS:gmatch'%S+' do VALID[c] = true end
  aeq(NUM_LET, ds.pairlen(VALID))

  -- color has lowercase as well as empty+space
  VALID[''] = true; VALID[' '] = true
  for k in pairs(M.Color) do
    mty.assertf(VALID[k], 'Color: %q is not in VALID', k)
  end

  -- CODES also has uppercase
  for c in LETTERS:gmatch'%S+' do VALID[c:upper()] = true end
  for k in pairs(M.CODES) do
    mty.assertf(VALID[k], 'CODES: %q is not in VALID', k)
  end
  aeq(NUM_LET     + 2, ds.pairlen(M.Color))
  aeq(NUM_LET * 2 + 2, ds.pairlen(M.CODES))
end)

T.test('code', function()
  local c = M.assertcode
  aeq('a',  c'a')
  aeq('Z',  c'Z')
  aeq('z',  c'z')
  aeq('z',  c' ')
  aeq('z',  c'')
  T.assertErrorPat('invalid ascii color: "O"', function() c'O' end)
end)

T.test('ascii', function()
  local W = Writer; local w = W{}
  local st = S.Styler{f=mty.Fmt{to=w}, style=S.ascii}
  st:styled('type', 'Type', ' ')
  T.assertEq(W{'[Type] '}, w)

  st:styled('keyword', 'keyword\n')
  T.assertEq(W{'[Type] keyword', ''}, w)
  st:styled('path', 'path/to/thing.txt', '\n')
  T.assertEq(W{'[Type] keyword', 'path/to/thing.txt', ''}, w)
  ds.clear(w)
  st:styled('h2', 'Header 2')
  T.assertEq(W{'## Header 2'}, w)

  st:styled('code', '\nsome code\n  more code', '\nnot code')
  T.assertEq(W{'## Header 2',
               '  some code', '    more code',
               'not code'}, w)
  ds.clear(w)
  w:write'blah blah '
  st:styled('code', 'inline code', ' blah blah')
  T.assertEq(W{'blah blah [$inline code] blah blah'}, w)

  ds.clear(w)
  st:styled('code', 'codething', ' blah blah')
  T.assertEq(W{'$codething blah blah'}, w)
end)
