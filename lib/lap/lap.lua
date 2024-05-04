
-- lap protocol globals
LAP_READY = LAP_READY or {}
LAP_FNS_SYNC  = LAP_FNS_SYNC  or {}
LAP_FNS_ASYNC = LAP_FNS_ASYNC or {}

local mty = require'metaty'
local ds = require'ds'
local heap = require'ds.heap'

local push = table.insert
local yield = coroutine.yield

local M = {_async = {}, _sync = {}}

M.formatCorErrors = function(corErrors, lvl)
  local f = {}
  lvl = lvl and (lvl + 1) or 2
  for _, corErr in ipairs(corErrors) do
    push(f, 'Coroutine error: '..tostring(corErr[1])..'\n')
    push(f, debug.traceback(corErr[1], corErr[2], lvl))
    push(f, '\n')
  end
  return table.concat(f)
end

-- Switch lua to synchronous mode
M.sync  =
(function()
  for _, fn in ipairs(LAP_FNS_SYNC)  do fn() end
  LAP_ASYNC = false
end)

-- Switch lua to asynchronous (yielding) mode
M.async =
(function()
  for _, fn in ipairs(LAP_FNS_ASYNC) do fn() end
  LAP_ASYNC = true
end)

-- schedule(fn) -> cor?
--   sync:  run the fn immediately and return nil
--   async: schedule the fn and return it's coroutine
M._async.schedule = function(fn, id)
  local cor = coroutine.create(fn)
  LAP_READY[cor] = id or true
  return cor
end
M._sync.schedule = function(fn) fn() end

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
M.Recv.recv = function(r)
  local deq = r.deq
  while (#deq == 0) and (r._sends and not ds.isEmpty(r._sends)) do
    r.cor = coroutine.running(); yield()
  end
  return deq()
end
M.Recv.__call = M.Recv.recv

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
M.Send.send = function(send, val)
  local r = assert(send._recv, 'send when closed')
  r.deq:push(val);
  if r.cor then LAP_READY[r.cor] = 'ch.send' end
end
M.Send.__call = M.Send.send
M.Send.__len = function(send)
  local r = send._recv; return r and #r or 0
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
  yield() -- forget until resumed by last completed child
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
  while not next(self.done) do yield() end
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
M.monoCmp  = function(i1, i2) monoLt(i1[1], i2[1]) end
M.LAP_UPDATE = {
  [true] = function(lap, cor) LAP_READY[cor] = true end,
  sleep = function(lap, cor, sleepSec)
    lap.monoHeap:add{lap:monoFn() + sleepSec, cor}
  end,
  poll = function(lap, cor, fileno, events)
    lap.pollList:insert(fileno, events)
    lap.pollMap[fileno] = cor
  end,
}

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
  ex.monoHeap = ex.monoHeap or heap.Heap{cmp = M.monoCmp}
  ex.pollMap  = ex.pollMap  or {}
  return mty.construct(T, ex)
end
M.Lap.sleep = M.LAP_UPDATE.sleep
M.Lap.poll  = M.LAP_UPDATE.poll
M.Lap.execute = function(lap, cor)
  if not cor then return end
  local ok, kind, a, b = coroutine.resume(cor)
  if not ok   then return kind end -- error
  if not kind then return      end   -- forget
  local fn = M.LAP_UPDATE[kind]
  if not fn then error('unknown kind '..kind) end
  fn(lap, cor, a, b)
end
M.Lap.__call = function(lap)
  local errors = nil
  if next(LAP_READY) then
    local ready = LAP_READY; LAP_READY = {}
    for cor in pairs(ready) do
      local err = lap:execute(cor)
      if err then
        errors = errors or {};
        push(errors, {cor, err})
      end
    end
  end

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
      LAP_READY[ds.popk(pm, fileno)] = 'poll'
      pl:remove(fileno)
    end
  else lap.sleepFn(sleep) end
  return errors
end
M.Lap.isDone = function(lap)
  return not (next(LAP_READY) or (#lap.monoHeap > 0) or next(lap.pollMap))
end
M.Lap.run = function(lap, fns)
  LAP_READY = LAP_READY or {}
  assert(lap:isDone(), "cannot run non-done Lap")
  if type(fns) == 'function' then LAP_READY[coroutine.create(fns)] = 'run'
  else
    for i, fn in ipairs(fns) do
      LAP_READY[coroutine.create(fn)] = 'run'
    end
  end
  while not lap:isDone() do
    local errors = lap(); if errors then
      error(M.formatCorErrors(errors))
    end
  end
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
