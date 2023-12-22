
METATY_CHECK = true

local mty = require'metaty'
local ds = require'ds'

local test, assertEq; mty.lrequire'civtest'

local M = require'rnv'


test('simple', function()
  assertEq(
    '0 1\t2\t"hi',
    table.concat(M.serialize{{{1, 2, 'hi'}}}, '\n')
  )
end)
