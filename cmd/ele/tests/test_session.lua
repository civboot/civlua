-- Test display functionality (not mutation)

local T = require'civtest'
local ds, lines = require'ds', require'lines'
local term = require'civix.term'
local etest = require'ele.testing'
local edit = require'ele.edit'
local Buffer = require'rebuf.buffer'.Buffer
local es = require'ele.session'
local bindings = require'ele.bindings'

local aeq = T.assertEq

local y = function(v) coroutine.yield(v or true) end

local function run(s)
  while (#s.keys + #s.events > 0) do coroutine.yield(true) end
end

local lines3 = '1 2 3 4 5\n 2 4 6 8\n'
T.asyncTest('session', function()
  local s = es.Session:test(); local ed = s.ed
  local ke, sk = ed.ext.keys, s.keys:sender()
  local b, bi = ed:buffer()
  local e = ed:focus(b)
  aeq('command', ed.mode)

  s:start()
  sk'i'; run(s)
    aeq(bindings.command, ke.next) -- selected in keyinput
    aeq('insert', ed.mode)         -- next mode

  sk'9'; sk'space'; run(s)
    aeq('9 ', b.dat[1])
end)
