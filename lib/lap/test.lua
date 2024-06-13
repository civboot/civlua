METATY_CHECK = true

local T = require'civtest'
local mty = require'metaty'
local ds = require'ds'
local M  = require'lap'

local push, yield = table.insert, coroutine.yield

T.asyncTest('schedule', function()
  local i = 0
  local cor = M.schedule(function()
    for _=1,3 do i = i + 1; yield(true) end
    i = 99
  end)
  T.assertEq('scheduled', LAP_READY[cor])
  for ei=1, 3 do
    assert(LAP_READY[cor])
    T.assertEq(ei, i); yield(true)
  end
  T.assertEq(nil, LAP_READY[cor])
  T.assertEq(99, i)
end)

T.asyncTest('ch', function()
  local r = M.Recv(); local s = r:sender()

  local res = {}
  M.schedule(function()
    for v in r do push(res, v) end
  end)
  T.assertEq({}, res)
  yield(true); T.assertEq({}, res)
  s(10);       T.assertEq({}, res)
  yield(true); T.assertEq({10}, res)

  s(11); s(12); T.assertEq({10}, res)
  yield(true);  T.assertEq({10, 11, 12}, res)
  T.assertEq({}, r:drain())
end)
