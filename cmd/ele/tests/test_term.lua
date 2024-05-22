-- Test display functionality (not mutation)

local T = require'civtest'
local ds, lines = require'ds', require'lines'
local term = require'civix.term'
local et   = require'ele.testing'
local edit = require'ele.edit'
local Buffer = require'rebuf.buffer'.Buffer

local str = require'metaty'.tostring

local DIAGONAL =
  "[height=4 width=30]\n"
.."    [height=4 width=30]\n"
.."        [height=4 width=30]\n"
..""
local SETLEFT =
  "set:\n"
.."set:\n"
.."set:\n"
.."set:"
local SETCOLGRID =
  "set:5 7 9 1 3 5 7 9 1 3 5 7 9\n"
.."set: 6 8 0 2 4 6 8 0 2 4 6 8 0\n"
.."set:5 7 9 1 3 5 7 9 1 3 5 7 9\n"
.."set: 6 8 0 2 4 6 8 0 2 4 6 8 0"

T.lapTest('direct', function()
  local t = term.FakeTerm(4, 30)
  et.diagonal(t)
  T.assertEq(DIAGONAL, str(t))
  local left = 'set:'
  et.setleft(t, left)
  T.assertEq(SETLEFT, str(t))
  et.setcolgrid(t, #left + 1)
  T.assertEq(SETCOLGRID, str(t))
end)

local lines3 =
  'line1\n'
..'  line2\n'
..'    line3'

local L_2h5w =
  "line1\n"
.."  lin\n"

local L_2l3c2h5w =
  "\n"
.."  line1\n"
.."    lin"

T.test('edit', function()
  local e = edit.Edit(nil, Buffer.new(lines3))
  T.assertEq(3, #e.buf.gap)
  T.assertEq(3, #e.buf)
  T.assertEq(3, #e)
  local ft = term.FakeTerm(3, 10)
  e.tl, e.tc, e.th, e.tw = 1, 1, 3, 10
  e:draw(ft, true)
  T.assertEq(lines3, str(ft))

  e.th, e.tw = 2, 5
  ft:clear(); e:draw(ft, true)
  T.assertEq(L_2h5w, str(ft))

  e.tl, e.tc = 2, 3
  ft:clear(); e:draw(ft, true)
  T.assertEq(L_2l3c2h5w, str(ft))
end)
