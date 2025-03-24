local mty = require'metaty'
local ds  = require'ds'
local lines = require'lines'
local T = require'civtest'
local Diff, Keep, Change; local M = ds.auto'vcds'
local push = table.insert

T.create_anchor = function()
  local base = {'1', '1', ' ', '2', '3', '3', ' ', '1', '2'}
  T.eq({}, M.createAnchorTop(base, 0, 2))
  T.eq({Diff(1, '@', '1')}, M.createAnchorTop(base, 1, 2))
  T.eq({
    Diff(1, '@', '1'),
    Diff(2, '@', '1'),
  }, M.createAnchorTop(base, 2, 2))
  T.eq({
    Diff(2, '@', '1'),
    Diff(3, '@', ' '),
    Diff(4, '@', '2'),
  }, M.createAnchorTop(base, 4, 2))

  T.eq({},  M.createAnchorBot(base, 10, 2))
  T.eq({Diff(9, '@', '2')}, M.createAnchorBot(base, 9, 2))
  T.eq({
    Diff(8, '@', '1'),
    Diff(9, '@', '2'),
  }, M.createAnchorBot(base, 8, 2))
  T.eq({
    Diff(7, '@', ' '),
    Diff(8, '@', '1'),
    Diff(9, '@', '2'),
  }, M.createAnchorBot(base, 7, 2))
end

T.patch = function()
  local base = {'2', '2', '2', '5', '5_', '7_', '9'}

  local diffs = {
    Diff('+', 1, '1'),  -- 1
    Diff(1,   2, '2'),  -- 2 keep
    Diff(2,   3, '2'),  -- 2 keep
    Diff(3,   4, '2'),  -- 2 keep
  }

  local change2 = {
    Diff('+', 5, '3'),  -- 3
    Diff('+', 6, '4'),  -- 4
    Diff(4,   7, '5'),  -- 5 keep
    Diff('+', 8, '6'),  -- 6
    Diff('+', 9, '7'),
    Diff('+',10, '8'),
    Diff('+',11, '9'),  -- 9
    Diff(5, '-', '5_'), -- 10
    Diff(6, '-', '7_'), -- 11
  }
  ds.extend(diffs, change2)
  push(diffs, Diff(7,  12, '9'))  -- 12 keep

  local changes = M.toChanges(diffs)
  T.eq({
    Change{rem=0, add={'1'}},                -- 1
    Keep{num=3},                             -- 2,2,2
    Change{rem=0, add={'3', '4'}},           -- 3
    Keep{num=1},                             -- 4
    Change{rem=2, add={'6', '7', '8', '9'}}, -- 5
    Keep{num=1},
  }, changes)
  T.eq(diffs, M.toDiffs(base, changes))

  local changesB = M.toChanges(diffs, true)
  T.eq({
    Change{rem={}, add={'1'}},
    Keep{'2', '2', '2'},
    Change{rem={}, add={'3', '4'}},
    Keep{'5'},
    Change{
      rem={'5_', '7_'},
      add={'6', '7', '8', '9'}
    },
    Keep{'9'},
  }, changesB)
  T.eq(diffs, M.toDiffs(base, changesB))

  local p = M.Picks(base, changes, {anchorLen=2})
  T.eq({1, 1}, {p:groupChanges(1)})
  T.eq({3, 5}, {p:groupChanges(2)})
  T.eq({
    Diff('+',   1, '1'),
    Diff(  1, '@', '2'),
    Diff(  2, '@', '2'),
  }, p())

  local patch = {
    Diff(  2, '@', '2'),
    Diff(  3, '@', '2'),
  }
  ds.extend(patch, change2)
  push(patch, Diff(7, '@', '9'))
  T.eq(patch, p())
end

local function findAnchorTest(expectBl, expectLines, base, anchors, above)
  local baseMap = lines.map(base)
  local aDiffs = {}; for _, a in ipairs(anchors) do
    push(aDiffs, Diff(-1, '@', a))
  end
  T.eq({expectBl, expectLines}, {M.findAnchor(base, baseMap, aDiffs, above)})
end

T.find_anchor = function()
  local tl = {'a', 'b', 'b', 'c', '', 'd', 'b', 'a'}
  -- above
  findAnchorTest(1, 2, tl, {'a', 'b'},      true)
  findAnchorTest(2, 2, tl, {'b', 'b'},      true)
  findAnchorTest(2, 2, tl, {'a', 'b', 'b'}, true)
  findAnchorTest(4, 1, tl, {'b', 'c'},      true)
  findAnchorTest(7, 2, tl, {'b', 'a'},      true)

  findAnchorTest(nil, nil, tl, {'a'},       true)
  findAnchorTest(nil, nil, tl, {'b'},       true)

  -- below
  findAnchorTest(2, 2, tl, {'b', 'b'},      false)
  findAnchorTest(3, 2, tl, {'b', 'c'},      false)
  findAnchorTest(4, 1, tl, {'c'},           false)
  findAnchorTest(7, 2, tl, {'b', 'a'},      false)

  findAnchorTest(nil, nil, tl, {'a'},       false)
  findAnchorTest(nil, nil, tl, {'b'},       false)
end

T.create_patch = function()
  local base = {'1', '2', '3', '4', '5', '6', '7'}
  local baseMap = lines.map(base)
   T.eq(M.Patch{bl=0,
     '0.a',
   }, M.createPatch(base, baseMap,
     { Diff('+', 1, '0.a') }
   ))
end
