-- Test event handling actions

local T = require'civtest'
local M = require'ele.actions'
local ds, lines = require'ds', require'lines'
local edit = require'ele.edit'
local Buffer = require'rebuf.buffer'.Buffer

local newData = function(lines)
	return {
    edit = edit.Edit(nil, Buffer.new(lines)),
  }
end

local lines3 =
  '1 3 5 7 9\n'
..'  3 5\n'
..'1 3 5 7 9\n'

T.test('move', function()
  local d = newData(lines3); local e = d.edit
  local function assertMove(mv, ev, l, c)
    ev.move = mv; M.move(d, ev)
    T.assertEq({l, c}, {e.l, e.c})
  end

  T.assertEq({1, 1}, {e.l, e.c})

  -- move some cols
  assertMove(nil, {cols=1}, 1, 2)
  assertMove(nil, {cols=-3}, 1, 1)

  -- forword/backword
  assertMove('forword',  {},        1, 3)
  assertMove('forword',  {times=2}, 1, 7)
  assertMove('backword', {},        1, 5)
  assertMove('forword',  {times=5}, 1, 10)

  -- move lines
  e.l, e.c = 1, 9; assertMove('lines', {lines=1}, 2, 6)
  e.l, e.c = 1, 9; assertMove('lines', {lines=2}, 3, 9)

  -- find
  e.l, e.c = 1, 1
  assertMove('find',     {find='3'},     1, 3)
  assertMove('find',     {find='9'},     1, 9)
  assertMove('findback', {findback='1'}, 1, 1)
end)
