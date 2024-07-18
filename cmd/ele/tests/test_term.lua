-- Test display functionality (not mutation)

local T = require'civtest'
local ds, lines = require'ds', require'lines'
local et   = require'ele.testing'
local edit = require'ele.edit'
local Buffer = require'rebuf.buffer'.Buffer
local Fake = require'vt100.testing'.Fake

local str = require'metaty'.tostring

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
  T.assertEq(3, #e.buf.dat)
  T.assertEq(3, #e.buf)
  T.assertEq(3, #e)
  local ft = Fake{h=3, w=10}
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
