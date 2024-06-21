METATY_CHECK = true

local T = require'civtest'
local mty = require'metaty'
local ds = require'ds'
local M  = require'lap'

local push, yield = table.insert, coroutine.yield
local co = coroutine

T.asyncTest('schedule', function()
  local i = 0
  local cor = M.schedule(function()
    for _=1,3 do i = i + 1; yield(true) end
    i = 99
  end)
  T.assertEq('scheduled', LAP_READY[cor])
  for ei=0, 3 do
    assert(LAP_READY[cor])
    T.assertEq(ei, i); yield(true)
  end
  T.assertEq(nil, LAP_READY[cor])
  T.assertEq(99, i)
end)

T.asyncTest('ch', function()
  local r = M.Recv(); local s = r:sender()

  local t = {}
  M.schedule(function()
    for v in r do push(t, v) end
  end)
  T.assertEq({}, t);
  yield(true); T.assertEq({}, t)
  s(10);       T.assertEq({}, t)
  yield(true); T.assertEq({10}, t)

  s(11); s(12); T.assertEq({10}, t)
  yield(true);  T.assertEq({10, 11, 12}, t)
  T.assertEq({}, r:drain())

  ds.clear(t)
  s(13); T.assertEq({13}, r:drain())
  yield(true); T.assertEq({}, t)
end)

T.test('execute', function()
  local l = M.Lap{}
  local v = 0
  local res = l:execute(co.create(
    function() v = 3; yield'forget' end
  ))
  T.assertEq(3, v)
  T.assertEq(nil, res)
  local res = l:execute(co.create(
    function() yield'foo' end
  ))
  T.assertEq('unknown kind: foo', res)

  local errFn = function() error'bar' end
  local res = l:execute(co.create(errFn))
  T.assertMatch(': bar', res)
end)

