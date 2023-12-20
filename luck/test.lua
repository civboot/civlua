METATY_CHECK = true

local mty = require'metaty'
local test, assertEq, assertErrorPat; mty.lrequire'civtest'
local M = require'luck'

test("simple", function()
  local s = M.luck'testdata/small.luck'
  assertEq(1, 1)
  assertEq({i=8, s="hello", t={1, 2, v=3}}, s)
end)

