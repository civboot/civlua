local mty = require'metaty'
local test, assertEq; mty.lrequire'civtest'
local Diff, Keep, Change; local M = mty.lrequire'ds.diff'

test('basic', function()
  local base = {'1', '2', '5', '5_', '7_', '9'}
  local diffs = {
    Diff('+', 1, '0'),
    Diff(1,   2, '2'),
    Diff('+', 3, '3'),
    Diff('+', 4, '4'),
    Diff(2,   5, '5'),
    Diff('+', 6, '6'),
    Diff('+', 7, '7'),
    Diff('+', 8, '8'),
    Diff('+', 9, '9'),
    Diff(3, '-', '5_'),
    Diff(4, '-', '7_'),
    Diff(5,  10, '9'),
  }
  -- assertEq({}, diffs)
  local changes = M.toChanges(diffs)
  local patches = {
    Keep{num=12},
  }
  -- assertEq(patches, changes)

end)
