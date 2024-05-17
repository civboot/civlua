local T = require'civtest'
local ds = require'ds'
local term = require'civix.term'
local et = require'ele.testing'

local str = require'metaty'.tostring

local DIAGONAL =
  "[height=4 width=30]           \n"
.."    [height=4 width=30]       \n"
.."        [height=4 width=30]   \n"
.."                              "
local SETLEFT =
  "set:                          \n"
.."set:                          \n"
.."set:                          \n"
.."set:                          "
local SETCOLGRID =
  "set:5 7 9 1 3 5 7 9 1 3 5 7 9 \n"
.."set: 6 8 0 2 4 6 8 0 2 4 6 8 0\n"
.."set:5 7 9 1 3 5 7 9 1 3 5 7 9 \n"
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


