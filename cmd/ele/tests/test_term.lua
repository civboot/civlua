-- Test display functionality (not mutation)

local T = require'civtest'
local fmt = require'fmt'
local ds, lines = require'ds', require'lines'
local et   = require'ele.testing'
local edit = require'ele.edit'
local Buffer = require'lines.buffer'.Buffer
local Fake = require'vt100.testing'.Fake

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

T.edit = function()
  local e = edit.Edit{buf=Buffer.new(lines3)}
  T.eq(3, #e.buf.dat)
  T.eq(3, #e.buf)
  T.eq(3, #e)
  local ft = Fake{h=3, w=10}
  e.tl, e.tc, e.th, e.tw = 1, 1, 3, 10
  e:draw(ft, true)
  T.eq(lines3, fmt(ft))

  e.th, e.tw = 2, 5
  ft:clear(); e:draw(ft, true)
  T.eq(L_2h5w, fmt(ft))

  e.tl, e.tc = 2, 3
  ft:clear(); e:draw(ft, true)
  T.eq(L_2l3c2h5w, fmt(ft))
end

