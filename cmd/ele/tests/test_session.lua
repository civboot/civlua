-- Test display functionality (not mutation)

local T = require'civtest'
local ds, lines = require'ds', require'lines'
local term = require'civix.term'
local etest = require'ele.testing'
local edit = require'ele.edit'
local Buffer = require'rebuf.buffer'.Buffer
local es = require'ele.session'

local str = require'metaty'.tostring

local lines3 = '1 2 3 4 5\n 2 4 6 8\n'
T.test('session', function()
  local s = es.Session:test(); local ed = s.ed
  local b, bi = ed:buffer()
  local e = ed:focus(b)
end)
