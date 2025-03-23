METATY_CHECK = true

local pkg = require'pkglib'
local ds = require'ds'
local test, T.eq; ds.auto'civtest'

local action = require'ele.action'
local A = action.Actions

test('spaces', function()
  T.eq(2, action.wantSpaces(1, 2))
  T.eq(1, action.wantSpaces(2, 2))
  T.eq(2, action.wantSpaces(3, 2))

  T.eq(4, action.wantSpaces(1, 4))
  T.eq(3, action.wantSpaces(2, 4))
  T.eq(2, action.wantSpaces(3, 4))
  T.eq(1, action.wantSpaces(4, 4))
end)
