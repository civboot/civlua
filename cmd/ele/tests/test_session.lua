-- Test display functionality (not mutation)

local T = require'civtest'
local mty = require'metaty'
local ds, lines = require'ds', require'lines'
local log = require'ds.log'
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
  local lt = log.LogTable{}

  s:start()
  aeq('command', ed.mode)

  s:play'Z' -- unknown
  aeq(1, #ed.error)
  T.assertMatch('unbound chord: Z', ed.error[1].msg)
  ds.clear(ed.error)

  s:play'i'
    aeq('insert', ed.mode) -- next mode
    aeq(bindings.command, ke.next) -- selected in keyinput

  aeq(lt, ed.error)

  s:play'9 space'
    aeq('9 ', b.dat[1])
  aeq(lt, ed.error)

  ed.run = false
end)
