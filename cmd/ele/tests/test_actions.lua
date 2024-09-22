-- Test event handling actions

local fmt = require'fmt'
local T = require'civtest'
local ds = require'ds'
local M = require'ele.actions'
local edit = require'ele.edit'
local Ed = require'ele.Ed'
local Buffer = require'rebuf.buffer'.Buffer

local newEd = function(lines)
  return Ed{
    edit = edit.Edit(nil, Buffer.new(lines)),
  }
end

local lines3 =
  '1 3 5 7 9\n'
..'  3 5\n'
..'1 3 5 7 9\n'

T.test('move', function()
  local d = newEd(lines3); local e = d.edit
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

T.test('remove', function()
  local d = newEd(lines3); local e, b = d.edit, d.edit.buf
  local function assertRemove(mv, ev, l, c)
    ev.move = mv; M.remove(d, ev)
    T.assertEq({l, c}, {e.l, e.c})
  end

  T.assertEq({1, 1}, {e.l, e.c})
  assertRemove('forword', {}, 1, 1) -- remove word (end at 1.1)
    T.assertEq('3 5 7 9', b[1])
    T.assertEq('  3 5', b[2])
  assertRemove('find', {find='7', cols=-1}, 1, 1) -- remove before 7
    T.assertEq('7 9', b[1])
  assertRemove('lines', {lines=0, times=2}, 1, 1) -- remove two lines
    T.assertEq('1 3 5 7 9\n', fmt(b.dat))
  e.c = 4; assertRemove(nil, {off=-1, cols1=-1}, 1, 3) -- backspace delete '3'
    T.assertEq('1  5 7 9\n', fmt(b.dat))
  e.c = 4; assertRemove(nil, {off=-1}, 1, 3) -- backspace delete ' 5'
    T.assertEq('1  7 9\n', fmt(b.dat))
end)

T.test('insert', function()
  local d = newEd'1 2 3\n4 5 6'; local e, b = d.edit, d.edit.buf
  local function assertInsert(txt, ev, l, c)
    ev[1] = txt; M.insert(d, ev)
    T.assertEq({l, c}, {e.l, e.c})
  end
  T.assertEq({1, 1}, {e.l, e.c})
  assertInsert('4 5 ', {}, 1, 5)
    T.assertEq('4 5 1 2 3', b[1])
    T.assertEq('4 5 6',     b[2])
  assertInsert('6 7\n', {}, 2, 1)
    T.assertEq('4 5 6 7\n1 2 3\n4 5 6', fmt(b.dat))
end)
