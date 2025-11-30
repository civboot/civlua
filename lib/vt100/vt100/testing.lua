--- helpers for testing/demoing vt100
local M = mod and mod'vt100.testing' or {}

local T = require'civtest'
local mty = require'metaty'
local ds = require'ds'
local log = require'ds.log'
local vt = require'vt100'
local co = coroutine

M.Fake = mty.extend(vt.Term, 'Fake')

M.Fake.resize = function(tm, l, c)
  assert(l and c, 'must pass l,c for Fake')
  tm.l, tm.c = l, c
  tm:clear()
end

M.Fake.draw  = ds.nosupport
M.Fake.input = ds.nosupport

--- start rawmode using tmpfiles
M.startTmp = function() --> out, err
  local err = io.tmpfile()
  vt.start(err)
  return err
end

--- Run function in a LAP environment with terminal started
--- and std in/out set correctly.
function M.run(fn)
  local lap = require'lap'
  local cx = require'civix'
  local fd = require'fd'
  local ioin, ioread = io.stdin, io.read

  local t = vt.Term{h=10, w=80}
  local stderr = M.startTmp()
  local r = lap.Recv{}
  local szTh = co.create(function() t:resize() end)
  local inTh = co.create(function() t:input(r) end)

  local ok, err = ds.try(function()
    -- make stdin async
    io.stdin, io.read = fd.stdin, fd.read
    fd.stdin:toNonblock()

    -- send size request and wait until it is recieved
    T.eq({true, 'forget'}, {ds.resume(szTh)})
    T.eq(szTh, t._waiting)

    while t._waiting do
      T.eq({true, 'poll', 0, fd.sys.POLLIN}, {ds.resume(inTh)})
    end
    T.eq(nil, t._waiting)
    T.eq(nil, r())
    T.eq({true}, {ds.resume(szTh)})
    T.eq('dead', coroutine.status(szTh))

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
  stderr:flush(); stderr:seek'set'
  local err = stderr:read'a'
  if #err > 0 then log.info('STDERR:\n%s', err) end
  stderr:close()
  assert(ok, 'got error, see stderr')
end

return M
