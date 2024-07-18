-- helpers for testing/demoing vt100
local M = mod and mod'vt100.testing' or {}

local T = require'civtest'
local mty = require'metaty'
local ds = require'ds'
local log = require'ds.log'
local vt = require'vt100'
local fd = require'fd'
local co = coroutine

M.Fake = mty.extend(vt.Term, 'Fake')

M.Fake.resize = function(tm, l, c)
  assert(l and c, 'must pass l,c for Fake')
  tm.l, tm.c = l, c
  tm:clear()
end

M.Fake.draw  = ds.nosupport
M.Fake.input = ds.nosupport

M.runWaiting = function(term, th)
  while term._waiting do
    T.assertEq({true, 'poll', 0, fd.sys.POLLIN}, {ds.resume(th)})
  end
end

-- start rawmode using tmpfiles
M.startTmp = function() --> out, err
  local out, err = io.tmpfile(), io.tmpfile()
  vt.start(out, err)
  return out, err
end

-- Run function in a LAP environment with terminal started
-- and std in/out set correctly.
function M.run(fn)
  local lap = require'lap'
  local cx = require'civix'
  local ioin, ioread = io.stdin, io.read

  local t = vt.Term{h=10, w=80}
  local stdout, stderr = M.startTmp()
  stdout:write'started vt100.testing.run()\n'

  local r = lap.Recv{}
  local szTh = co.create(function() t:resize() end)
  local inTh = co.create(function() t:input(r) end)

  local ok, err = ds.try(function()
    -- make stdin async
    io.stdin, io.read = fd.stdin, fd.read
    fd.stdin:toNonblock()

    -- send size request and wait until it is recieved
    T.assertEq({true, 'forget'}, {ds.resume(szTh)})
      T.assertEq(szTh, t._waiting)
    M.runWaiting(t, inTh)
      T.assertEq(nil, t._waiting)
      T.assertEq(nil, r())
    T.assertEq({true}, {ds.resume(szTh)})
      T.assertEq('dead', coroutine.status(szTh))
    log.info('term size: %s %s', t.h, t.w)
    fn(t)
  end)
  -- undo async stdin
  io.stdin, io.read = ioin, ioread
  fd.stdin:toBlock()

  vt.stop();
  io.flush()
  io.stderr:write('\nvt100.testing.run '..
    (ok and 'DONE' or ('ERROR:\n'..tostring(err)))
    ..'\n')
  stdout:flush();   stderr:flush()
  stdout:seek'set'; stderr:seek'set'
  local out, err = stdout:read'a', stderr:read'a'
  assert(#out > 0)
  if #out > 0 then log.info('STDOUT:\n%s', out) end
  if #err > 0 then log.info('STDERR:\n%s', err) end
  stdout:close(); stderr:close()
  assert(ok, 'got error, see stderr')
end

return M
