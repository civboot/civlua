
-- lap protocol globals
LAP_READY = LAP_READY or {}
LAP_FNS_SYNC  = LAP_FNS_SYNC  or {}
LAP_FNS_ASYNC = LAP_FNS_ASYNC or {}
LAP_TRACE = LAP_TRACE or {}

local mty = require'metaty'
local ds = require'ds'
local heap = require'ds.heap'

local sfmt = string.format
local push = table.insert
local yield, create  = coroutine.yield, coroutine.create
local resume, status = coroutine.resume, coroutine.status
local log = require'ds.log'
local errorFrom = ds.Error.from
local TRACE = log.LEVEL.TRACE

local M = {_async = {}, _sync = {}}

LAP_CORS = LAP_CORS or ds.WeakKV{}

M.formatCorErrors = function(corErrors)
  local f = mty.Fmt{}
  for _, ce in ipairs(corErrors) do
    push(f, 'Coroutine '); f(ce)
    push(f, '\n')
  end
  return table.concat(f)
end

-- Switch lua to synchronous mode
M.sync  =
(function()
  if not LAP_ASYNC then return end
  for _, fn in ipairs(LAP_FNS_SYNC)  do fn() end
  assert(not LAP_ASYNC)
end)

-- Switch lua to asynchronous (yielding) mode
M.async =
(function()
  if LAP_ASYNC then return end
  for _, fn in ipairs(LAP_FNS_ASYNC) do fn() end
  assert(LAP_ASYNC)
end)

-- yield(fn)
--   sync: noop
--   async: coroutine.yield
M._async.yield = yield
M._sync.yield  = function() end

-- schedule(fn) -> coroutine?
--   sync:  run the fn immediately and return nil
--   async: create and schedule returned coroutine
M._async.schedule = function(fn, ...)
  assert(select('#', ...) == 0, 'only function supported')
  local cor = create(fn)
  LAP_READY[cor] = 'scheduled'
  LAP_CORS[cor] = fn
  log.trace('schedule %s [%q]', cor, fn)
  return cor
end
M._sync.schedule = function(fn, ...) fn(...) end

----------------------------------
-- Ch: channel sender and receiver (Send/Recv)

-- Recv() -> recv: the receive side of channel.
--
-- Is considered closed when all senders are closed.
--
-- Notes:
-- * Use recv:sender() to create a sender. You can create
--   multiple senders.
-- * Use recv:recv() or simply recv() to receive a value.
-- * User sender:send(v) or simply sender(v) to send a value.
-- * recv:close() when done. Also closes all senders.
-- * #recv gets number of items buffered.
-- * recv:isDone() returns true when either recv is closed
--   OR all senders are closed and #recv == 0.
M.Recv = mty'Recv'{
  'deq    [Deq]',
  '_sends [WeakKV]',
  'cor    [thread]',
}
getmetatable(M.Recv).__call = function(T)
  return mty.construct(T, {deq=ds.Deq(), _sends=ds.WeakKV{}})
end
-- Close read side and all associated sends.
M.Recv.close =
(function(r)
  local sends = r._sends; if not sends then return end
  for s in pairs(ds.copy(sends)) do s:close() end
  r._sends = nil
end)
M.Recv.__close  = M.Recv.close
M.Recv.__len    = function(r) return #r.deq          end
M.Recv.isClosed = function(r) return r._sends == nil end
M.Recv.isDone = function(r)
  return (#r.deq == 0)
     and (not r._sends or ds.isEmpty(r._sends))
end
M.Recv.sender = function(r)
  local s = M.Send(r)
  assert(r._sends, 'sender on closed channel')[s] = true
  return s
end
M.Recv.hasSender = function(r)
  return r._sends and next(r._sends) and true or false
end
M.Recv.wait = function(r)
  while (#r.deq == 0) and (r._sends and not ds.isEmpty(r._sends)) do
    r.cor = coroutine.running(); yield'forget'
  end
end
M.Recv.recv = function(r) r:wait() return r.deq() end
M.Recv.__call = M.Recv.recv
-- drain the recv. This does NOT wait for new items.
M.Recv.drain = function(r) return r.deq:drain() end
M.Recv.__fmt = function(r, fmt)
  push(fmt, ('Recv{%s len=%s hasSender=%s}'):format(
    r:isClosed() and 'closed' or 'active',
    #r.deq, r:hasSender() and 'yes' or 'no'))
end

local function recvReady(r)
  if r.cor then LAP_READY[r.cor] = 'ch.push' end
end
-- Sender, created through ds.Recv.sender()
--
-- Is considered closed if the receiver is closed.  The receiver will
-- automatically close if it is garbage collected.
M.Send = mty'Send'{'_recv[Recv]'}
getmetatable(M.Send).__call = function(T, recv)
  return mty.construct(T, { _recv=assert(recv, 'missing Recv') })
end
M.Send.__mode = 'kv'
M.Send.close = function(send)
  local r = send._recv; if r then
    local sends = assert(r._sends)
    sends[send] = nil; send._recv = nil
    if r.cor and ds.isEmpty(sends) then
      LAP_READY[r.cor] = 'ch.close'
    end
  end
end
M.Send.__close = M.Send.close
M.Send.isClosed = function(s) return s._recv == nil end
M.Send._ready = function(r)
end
M.Send.push = function(send, val)
  local r = assert(send._recv, 'recv closed')
  r.deq:push(val); recvReady(r)
end
M.Send.extend = function(send, vals)
  local r = assert(send._recv, 'recv closed')
  r.deq:extendRight(vals); recvReady(r)
end
-- preemtive send
M.Send.pushLeft = function(send, val)
  local r = assert(send._recv, 'recv closed')
  r.deq:pushLeft(val); recvReady(r)
end
-- put vals at left (order preserved)
M.Send.extendLeft = function(send, vals)
  local r = assert(send._recv, 'recv closed')
  r.deq:extendLeft(vals); recvReady(r)
end
M.Send.__call = M.Send.push
M.Send.__len = function(send)
  local r = send._recv; return r and #r or 0
end
M.Send.__fmt = function(send, f)
  push(f, ('Send{active=%s}'):format(send:isClosed() and 'no' or 'yes'))
end

----------------------------------
-- all / Any

-- all(fns): resume when all of the functions complete
M._async.all = function(fns)
  local rcor, count, len = coroutine.running(), 0, #fns
  for _, fn in ipairs(fns) do
    assert(type(fn) == 'function')
    local cor = coroutine.create(function()
      fn(); count = count + 1
      if count == len then LAP_READY[rcor] = 'all-done' end
    end)
    LAP_READY[cor] = 'all-item'
  end
  yield'forget' -- forget until resumed by last completed child
end
M._sync.all = function(fns) for _, f in ipairs(fns) do f() end end

-- Any(fns): handle resuming and restarting multiple fns.
-- 
-- Call any:ignore() to stop the child threads from resuming
-- the current thread. This does NOT stop the child threads.
-- 
-- Example which handles multiple fns running simultaniously:
-- 
--   local any = lap.Any{fn1, fn2}:schedule()
--   while true do
--     local i = any:yield()
--     -- do something related to index i
--     any:restart(i) -- restart i to run again
--   end
M.Any = mty'Any'{
  'cor[thread]', 'fns[table]',
  'done[table]',
}
getmetatable(M.Any).__call = function(T, fns)
  local self = { cor = coroutine.running(), fns = {}, done = {} }
  for i, fn in ipairs(fns) do
    assert(type(fn) == 'function')
    push(self.fns, function()
      fn(); self.done[i] = true
      if self.cor then
        LAP_READY[self.cor] = 'any-done'
      end
    end)
    self.done[i] = true
  end
  return mty.construct(T, self)
end
M.Any.ignore = function(self) self.cor = nil end
-- schedule() -> self: ensure all fns are scheduled
M.Any.schedule =
(function(self)
  for i in pairs(self.done) do self:restart(i) end
end)
-- yield() -> fnIndex: yield until a fn index is done
M.Any.yield =
(function(self)
  while not next(self.done) do yield'forget' end
  return next(self.done)
end)
-- restart(i): restart fn at index
M.Any.restart =
(function(self, i)
  LAP_READY[coroutine.create(self.fns[i])] = 'any-item'
  self.done[i] = nil
end)

----------------------------------
-- Lap
M.lt1  = function(a, b) return a[1] < b[1] end
local LAP_UPDATE = {
  [true] = function(lap, cor) LAP_READY[cor] = true end,
  forget = ds.noop,
  sleep = function(lap, cor, sleepSec)
    if type(sleepSec) ~= 'number' then
      return sfmt('non-number sleep: %s', sleepSec)
    end
    lap.monoHeap:add{lap:monoFn() + sleepSec, cor}
  end,
  poll = function(lap, cor, fileno, events)
    if lap.pollMap[fileno] then return string.format(
      'two coroutines are both attempting to listen to fileno=%s\n'
      ..'Existing traceback:\n  %s',
      fileno,
      table.concat(ds.tracelist(debug.traceback(lap.pollMap[fileno])), '\n  ')
    )end
    lap.pollList:insert(fileno, events)
    lap.pollMap[fileno] = cor
  end,
}; M.LAP_UPDATE = LAP_UPDATE

-- A single lap of the executor loop
--
-- Example:
--   -- schedule your main fn, which may schedule other fns
--   lap.schedule(myMainFn)
--
--   -- create a Lap instance with the necessary configs
--   local Lap = lap.Lap{
--     sleepFn=civix.sleep, monoFn=civix.monoSecs, pollList=fd.PollList()
--   }
--
--   -- run repeatedly while there are coroutines to run
--   while next(LAP_READY) do
--     errors = Lap(); if errors then
--       -- handle errors
--     end
--     -- do other things in your application's executor loop
--   end
M.Lap = mty'Lap' {
  'sleepFn [function]',
  'monoFn  [function]',
  'monoHeap [Heap]',
  'defaultSleep [float]',
  'pollMap [table]',
[[pollList [PollList] Poll list data structure. Required methods:
* __len                   to get length with `#`
* insert(fileno, events)  insert the fileno+events into the poll list
* remove(fileno)          remove the fileno from poll list
* ready(self, durationSec) -> {filenos}
    poll for durationSec (float), return any ready filenos.
]],
}
M.Lap.defaultSleep = 0.01
getmetatable(M.Lap).__call = function(T, ex)
  ex.monoHeap = ex.monoHeap or heap.Heap{cmp = M.lt1}
  ex.pollMap  = ex.pollMap  or {}
  return mty.construct(T, ex)
end
M.Lap.sleep = M.LAP_UPDATE.sleep
M.Lap.poll  = M.LAP_UPDATE.poll
M.Lap.execute = function(lap, cor, note) --> errstr?
  if LOGLEVEL >= TRACE and LAP_TRACE[cor] then
    log.trace("execute %s %s %q [%q]", cor, status(cor), note, LAP_CORS[cor])
  end
  local ok, kind, a, b = resume(cor)
  if LOGLEVEL >= TRACE and LAP_TRACE[cor] then
    log.trace("finished %s [%q] -> %s, %q [%q , %q]",
      cor, LAP_CORS[cor], ok and 'ok' or '!err!',
      ds.brief(kind), ds.brief(a), ds.brief(b))
  end
  if not ok then return kind end -- error
  local fn = LAP_UPDATE[kind]
  if fn then return fn(lap, cor, a, b)
  elseif kind then return 'unknown kind: '..kind end
  return (status(cor) ~= 'dead')
     and 'non-dead coroutine yielded false/nil' or nil
end

M.Lap.__call = function(lap)
  local errors = nil
  if next(LAP_READY) then
    local ready = LAP_READY; LAP_READY = {}
    for cor, note in pairs(ready) do
      local err = lap:execute(cor, note)
      if err then
        errors = errors or {}
        push(errors, errorFrom(err, cor))
      end
    end
  end
  if errors then return errors end

  -- Check for asleep coroutines
  local mh = lap.monoHeap; local hpop = mh.pop
  local now, till = lap:monoFn()
  if next(LAP_READY) then till = now -- no sleep when there are ready
  else                    till = now + lap.defaultSleep end
  while true do -- handle mono (sleep)
    -- keep popping from the minheap until it is before 'now'
    local e = hpop(mh); if not e then break end
    if e[1] > now then
      mh:add(e); till = math.min(till, e[1])
      break
    end
    LAP_READY[e[2]] = 'sleep'
  end

  -- Poll or sleep before next loop
  local sleep = math.max(0, till - now)
  if next(lap.pollMap) then
    local pl, pm = lap.pollList, lap.pollMap
    for _, fileno in ipairs(pl:ready(sleep)) do
      local cor = ds.popk(pm, fileno); pl:remove(fileno)
      if LOGLEVEL >= TRACE and LAP_TRACE[cor] then
        log.trace('scheduling fileno=%s %q', fileno, LAP_CORS[cor])
      end
      LAP_READY[cor] = 'poll'
    end
  else lap.sleepFn(sleep) end
end
M.Lap.isDone = function(lap)
  return not (next(LAP_READY) or (#lap.monoHeap > 0) or next(lap.pollMap))
end
M.Lap.run = function(lap, fns, async, sync)
  local errors; async, sync = async or M.async, sync or M.sync
  assert(lap:isDone(), "cannot run non-done Lap")
  assert(not LAP_ASYNC, 'already in async mode')
  if type(fns) == 'function' then LAP_READY[coroutine.create(fns)] = 'run'
  else; for i, fn in ipairs(fns) do
    LAP_READY[coroutine.create(fn)] = 'run'
  end ; end
  async()
  while not lap:isDone() do
    errors = lap(); if errors then break end
  end
  sync()
  if errors then
    errors = M.formatCorErrors(errors)
    log.info('coroutine errors: %s', errors)
    error(errors)
  else log.info('Lap:run done. ready=%q, pm=%q', LAP_READY, lap.pollMap) end
  return lap
end

----------------------
-- Global Modifiers

local function toAsync()
  for k, v in pairs(M._async) do M[k] = v end
  LAP_ASYNC = true
end; push(LAP_FNS_ASYNC, toAsync)

local function toSync()
  for k, v in pairs(M._sync)  do M[k] = v end
  LAP_ASYNC = false
end; push(LAP_FNS_SYNC,  toSync)

if LAP_ASYNC then toAsync() else toSync() end

return M
