METATY_CHECK = true

local T = require'civtest'
local mty = require'metaty'
local fmt = require'fmt'
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
    fmt.assertf(VALID[k], 'Color: %q is not in VALID', k)
  end

  -- CODES also has uppercase
  for c in LETTERS:gmatch'%S+' do VALID[c:upper()] = true end
  for k in pairs(M.CODES) do
    fmt.assertf(VALID[k], 'CODES: %q is not in VALID', k)
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
