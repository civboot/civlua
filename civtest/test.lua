
local mty = require'metaty'
local test, assertEq, assertErrorPat, diffFmt;
mty.lrequire'civtest'

test('civtest', function()
  assertEq(1, 1)
  assertEq('hi', 'hi')
  assertEq({1, 2, a=5}, {1, 2, a=5})
  assertErrorPat('hi there', function() error('hi there bob') end)
end)

test('diffFmt', function()
  local b = {}; diffFmt(b, 'abc\n123\ndef', 'abc\n124\n')
  local exp = [[
! Difference line=2 (lines[3|3] strlen[11|8])
! EXPECT: 123
! RESULT: 124
            ^ (column 3)
! END DIFF
]]
  assertEq(exp, table.concat(b, ''))
end)

test('testGlobal', function()
  assertErrorPat('New globals: {"GLOBAL"}', function()
    test('  (globalErr)', function() GLOBAL = true end)
  end)
  GLOBAL = nil
end)
