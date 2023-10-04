METATY_CHECK = true

local test, assertEq
require'metaty'.lrequire'civtest'

local action = require'ele.action'
local A = action.Actions

test('spaces', function()
  assertEq(2, action.wantSpaces(1, 2))
  assertEq(1, action.wantSpaces(2, 2))
  assertEq(2, action.wantSpaces(3, 2))

  assertEq(4, action.wantSpaces(1, 4))
  assertEq(3, action.wantSpaces(2, 4))
  assertEq(2, action.wantSpaces(3, 4))
  assertEq(1, action.wantSpaces(4, 4))
end)
