METATY_CHECK = true

local CT = require'civtest'
local T = CT.Test()
local mty = require'metaty'
local ds = require'ds'
local M  = require'lap'

local push, yield = table.insert, coroutine.yield
local co = coroutine

CT.asyncTest('schedule', function()
  local i = 0
  local cor = M.schedule(function()
    for _=1,3 do i = i + 1; yield(true) end
    i = 99
  end)
  T.eq('scheduled', LAP_READY[cor])
  for ei=0, 3 do
    assert(LAP_READY[cor])
    T.eq(ei, i); yield(true)
  end
  T.eq(nil, LAP_READY[cor])
  T.eq(99, i)
end)

CT.asyncTest('ch', function()
  local r = M.Recv(); local s = r:sender()

  local t = {}
  M.schedule(function()
    for v in r do push(t, v) end
  end)
  T.eq({}, t);
  yield(true); T.eq({}, t)
  s(10);       T.eq({}, t)
  yield(true); T.eq({10}, t)

  s(11); s(12); T.eq({10}, t)
  yield(true);  T.eq({10, 11, 12}, t)
  T.eq({}, r:drain())

  ds.clear(t)
  s(13); T.eq({13}, r:drain())
  yield(true); T.eq({}, t)
end)

T.execute = function()
  local l = M.Lap{}
  local v = 0
  local res = l:execute(co.create(
    function() v = 3; yield'forget' end
  ))
  T.eq(3, v)
  T.eq(nil, res)
  local res = l:execute(co.create(
    function() yield'foo' end
  ))
  T.eq('unknown kind: foo', res)

  local errFn = function() error'bar' end
  local res = l:execute(co.create(errFn))
  T.matches(': bar', res)
end
