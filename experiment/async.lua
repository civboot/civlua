
local pkg = require'pkg'
local mt  = pkg'metaty'
local ds  = pkg'ds'
local heap = pkg'ds.heap'

local push, pop = table.insert, table.remove
local sfmt = string.format
local resume, newcor = coroutine.resume, coroutine.create
local yield = coroutine.yield

local EXECUTOR_ERR = "must set ASYNC_EXECUTOR"

----------------------------------
-- Await instance creation
-- These aren't real "types" as they don't have a metatable.
-- However, they DO all have the field 'awaitKind'.

M.getCor    = function(aw) return aw[0]  end
M.getParent = function(aw) return aw[-1] end

local function _await(aw, awaitKind)
  aw.awaitKind = awaitKind
  return aw
end

local IMM_READY = ds.Imm{awaitKind='ready'}
M.ready = mt.doc[[
ready() -> Await{kind=ready}
Await until next loop. Prevents any sleeps.

Note: it is called "ready" since the coroutine is already ready to run
  but is being polite.
]](function() return IMM_READY end)

M.listen = mt.doc[[
listen(aw) -> Await{kind=listen}
Sets Executor.listen[aw] = Scheduled

Note: Typically another coroutine has a way to access the aw instance and
  call `notify(aw)` which moves the Scheduled instance into ex.ready.
Example: see the implementation of Send and Recv channels.
]](function() return {awaitKind='listen'} end)

M.done = mt.doc[[
done(isDoneFn) -> Await{kind=done}
Await until isDone() returns true.

Note: the loop may still sleep for up to it's defaultSleep amount.
]](function(isDoneFn)
  assert(mt.callable(isDoneFn), 'isDoneFn must be callable')
  local aw = _await({isDone=isDoneFn}, 'done')
  return aw
end)

M.mono = mt.doc[[
mono(time, parent) -> Await{kind=mono}
Restart coroutine sometime after the system monotomic timer >= time.
Affects the maximum length of loop sleep.
]](function(mono, parent)
  return _await({mono=mono}, 'mono', parent)
end)
local monoLt = rawget(ds.Duration, '__lt')
M.awaitMonoCmp = function(i1, i2) monoLt(i1[1], i2[1]) end -- for Executor

M.poll = mt.doc[[poll(...) -> Await{kind=poll}
When yielded to an executeLoop, restart the coroutine after the system's
poll(...). Returns it as a valid fileid. The specific implementation
depends on the Executor.
]](function(t) return _await(t, 'poll') end)

M.handleErrorDefault = function(err, aw, cor)
  error(ds.coroutineErrorMessage(cor, err), 2)
end

local checkAnyAll = function(aw)
  return (type(aw.finished) ~= 'table') and 'requires .finished table'
      or (type(aw.children) ~= 'table') and 'requires children table'
      or (type(aw.children.count) ~= 'number') and 'requires children.count'
      or nil
end
local AW_CHECK = {
  ready = ds.retFalse,
  listen = ds.retFalse,
  done = function(aw)
    return (type(aw.isDone) == 'function')
      or 'aw.isDone must be a function'
  end,
  mono = function(aw)
    return (mt.type(aw.mono) == ds.Duration)
      or 'aw.mono must have type mt.Duration'
  end,
  poll = function(aw)
    local n = ' must be a number'
    if type(aw.fileno) ~= 'number' then return 'aw.fileno'..n end
    if type(aw.events) ~= 'number' then return 'aw.events'..n end
  end,
  any = checkAnyAll, all = checkAnyAll,
}

M.checkAwait = mt.doc[[
checkAwait(awaiter) -> errorMsg
Checks the Await instance for errors and returns error message if one is
found.
]](function(aw)
  if type(aw.awaitKind) ~= 'string' then
    return 'must have string field awaitKind'
  end
  local fn = AW_CHECK[aw.awaitKind]; if not fn then return sfmt(
    'aw.awaitKind is not a recognized kind: %s', aw.awaitKind
  )end
  return fn(aw)
end)

-- Note: when schedule/execute receives an any/all Await instance, it moves the
-- parent/children to the Scheduled instance and sets aw to an IMM instance.
local IMM_ANY_ALL = {any=ds.Imm{awaitKind='any'}, all=ds.Imm{awaitKind='all'}}

local function anyAll(kind, children)
  local err = kind..' must only be schedule instances'
  local chs = {count=#children}
  for _, s in ipairs(children) do
    assert(mt.ty(s) == M.Scheduled, err)
    chs[s] = true;
  end
  return {awaitKind=kind, children=chs, finished={}}
end

M.any = mt.doc[[
any{schedules} -> Await{...schedules...}
Await a list of schedules, resuming when ANY are finished.
]](function(schs) return anyAll('any', schs) end)

M.all = mt.doc[[
all{schedules} -> Await{...schedules...}
Await a list of schedules, resuming when ALL are finished.
]](function(schs) return anyAll('all', schs) end)

----------------------------------
-- Scheduled
M.Scheduled = mt.record'Scheduled'
  :field'aw':fdoc'The Await instance we are waiting for'
  :fieldMaybe('cor', 'thread'):fdoc'Optional coroutine to resume/run'
  :fieldMaybe'parent':fdoc'parent Scheduled instance'
  :fieldMaybe'children':fdoc'table of children (keys=Scheduled) and .count'
  :fieldMaybe'finished':fdoc'list of finished (removed) children in order'

M.notify = mt.doc[[
notify(aw) -> (), notify ASYNC_EXECUTOR that await instance is ready.
]](function(aw)
  assert(aw.awaitKind == 'listen', 'notify on non-listen Await')
  local ex = assert(ASYNC_EXECUTOR, EXECUTOR_ERR)
  local sch = ex.listen[aw]; if sch then
    ex.listen[aw] = nil; ex.ready[sch] = true
  end
end)

M.schedule = mt.doc[[
schedule(fn) -> Scheduled
Schedule fn on ASYNC_EXECUTOR. The scheduled coroutine will be run
on the next loop (this function returns without resuming it).

Note: converts fn to a coroutine if it is not already type=="thread".
]](function(fn)
  local ex = assert(ASYNC_EXECUTOR, EXECUTOR_ERR)
  if type(fn) == 'function' then fn = coroutine.create(fn) end
  assert(type(fn) == 'thread', 'can only schedule a fn or coroutine')
  local sch = M.Scheduled{aw=IMM_READY, cor=fn}
  ex.ready[sch] = true
  return sch
end)

----------------------------------
-- Executor{} and schedule()
M.executorUnsuported = function() error('method not supported', 2) end

M.Executor = mt.doc[[
executor(ex) -> ex

The executor instance is the interface between the OS and Lua. It must
have the following methods for the corresponding Await instances to
be supported:

  ex:mono() -> Duration: return the Duration (mono time)
    default: throw unsupported

  ex:pollAwait(aw, duration) -> isReady
    poll a single Await instance of kind=poll
    default: throw unsupported

  ex:poll(duration) -> {filenos}
    perform a poll on the ex.pollList (see field below) returning a list of
    ready filenos.
    default: throw unsupported

  ex:handleError(err, aw, cor)
    handle an error in a coroutine, typically by logging or panicing.
    default=ds.async.handleErrorDefault

  The following fields are added as normal tables if not present. They
  are lists of Scheduled instances to execute with Await instances of
  the named types.
    ready    done    any    all

  These are a slightly different type. The default is still an empty instance:
    monoHeap       ds.heap.Heap (minheap) of {Duration, Scheduled}
    pollMap        table of fileno -> Scheduled

  pollList is special and may only be supported on some platforms (else nil).
  It must have the following methods:
    __len                  to get length with `#`

    insert(fileno, events) insert the fileno+events into the poll list

    remove(fileno)         remove the fileno from poll list

    ready(self, Duration) -> {filenos}
      poll for duration, return any ready filenos
      if there are no filenos this MUST sleep for the given duration.
]](function(ex)
  ex = ex or {}
  for _, f in ipairs {
    'monoHeap', 'pollMap', 'ready', 'done', 'any', 'all',
  } do ds.getOrSet(ex, f, ds.newTable) end
  if mt.ty(ex.monoHeap) ~= heap.Heap then
    ex.monoHeap.cmp = M.awaitMonoCmp; ex.monoHeap = heap.Heap(ex.monoHeap)
  end
  local eu = M.executorUnsuported
  if not ex.mono        then ex.mono        = eu end
  if not ex.pollAwait   then ex.pollAwait   = eu end
  if not ex.poll        then ex.poll        = eu end
  if not ex.handleError then ex.handleError = M.handleErrorDefault end
  if not ex.listen      then ex.listen = ds.WeakK() end
  ex.defaultSleep = ex.defaultSleep or ds.Duration:fromMs(5)
  return ex
end)

local CHILD_FINISHED = { -- sch is the parent of a finished child
  any=function(ex, sch) ex.ready[sch] = true end,
  all=function(ex, sch)
    if #sch.finished >= sch.children.count then
      ex.ready[sch] = true
    end
  end,
}
-- finish(sch) -> (), finish the Scheduled instance.
-- Clears fields of Sch and notifies parents of completion, moving the parents
-- to the Executor if they are ready.
local function finish(sch, ex)
  sch.cor = nil; sch.aw = nil
  if sch.children then sch.children = nil; sch.finished = nil end
  local p = sch.parent; sch.parent = nil; if not p then return end
  assert(p.children[sch], 'parent does not have child registered')
  p.children[sch] = nil; push(p.finished, sch)
  CHILD_FINISHED[p.aw.awaitKind](ex, p)
end

-- When a coroutine yields any/all, move the relevant
-- fields to the sch and replace sch.aw with the immutable
-- type (that only has awaitKind).
--
-- The yielder continues to hold the same object and can track
-- the progress there.
local function updateAnyAll(ex, sch)
  local aw = sch.aw; sch.aw = IMM_ANY_ALL[aw.awaitKind]
  sch.children = aw.children; sch.finished = aw.finished
end
-- (ex, aw, cor) -> (): update executor with Await and coroutine
M.EX_UPDATE = {
  listen = function(ex, sch) ex.listen[sch.aw] = sch  end,
  ready  = function(ex, sch) ex.ready[sch] = true end,
  done   = function(ex, sch) push(ex.done, sch)   end,
  mono   = function(ex, sch) ex.monoHeap:add{assert(sch.aw.mono), sch} end,
  poll   = function(ex, sch)
    local aw = sch
    ex.pollList:insert(aw.fileno, aw.events)
    ex.pollMap[aw.fileno] = sch
  end,
  any = updateAnyAll, all = updateAnyAll,
}

-- execute(ex, sch) -> isDone, error
--
-- Execute (coroutine.resume) the scheduled item, updating the Executor and any
-- parents depending on result. isDone is returned if the item is done.
local function execute(ex, sch)
  local cor = sch.cor
  if not cor then finish(sch, ex); return true     end -- no coroutine
  local ok, aw = coroutine.resume(cor)
  if not ok  then finish(sch, ex);  return true, aw end -- error
  if not aw  then finish(sch, ex);  return true     end -- isDone
  sch.aw = aw; M.EX_UPDATE[aw.awaitKind](ex, sch)
end

----------------------------------
-- Ch: channel sender and receiver (Send/Recv)

M.Recv = mt.doc[[
Recv() -> recv: the receive side of channel.

Is considered closed when all senders are closed.

Notes:
* Use recv:sender() to create a sender. You can create
  multiple senders.
* Use recv:recv() or simply recv() to receive a value.
* User sender:send() or simply sender() to send a value.
* recv:close() when done. Also closes all senders.
* #recv gets number of items buffered.
* recv:isDone() returns true when either recv is closed
  OR all senders are closed and #recv == 0.
]](mt.record'Recv')
  :field('deq', ds.Deq)
  -- weak references of Sends. If nil then read is closed.
  :fieldMaybe('_sends', ds.WeakKV)
  :fieldMaybe'aw'
:new(function(ty_)
  return mt.new(ty_, {deq=ds.Deq(), _sends=ds.WeakKV{}})
end)
M.Recv.close = mt.doc[[Close read side and all associated sends.]]
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
    r.aw = M.listen(); yield(r.aw)
  end
  return deq()
end
M.Recv.__call = M.Recv.recv

M.Send = mt.doc[[
Sender, created through ds.Recv.sender()

Is considered closed if the receiver is closed.  The receiver will
automatically close if it is garbage collected.
]](mt.record'Send')
  :fieldMaybe('_recv', M.Recv)
:new(function(ty_, recv)
  return mt.new(ty_, { _recv=assert(recv, 'missing Recv') })
end)
M.Send.__mode = 'kv'
M.Send.close   = function(send)
  local r = send._recv; if r then
    local sends = assert(r._sends)
    sends[send] = nil; send._recv = nil
    if r.aw and ds.isEmpty(sends) then M.notify(r.aw) end
  end
end
M.Send.__close = M.Send.close
M.Send.isClosed = function(s) return s._recv == nil end
M.Send.send = function(send, val)
  local r = assert(send._recv, 'send when closed')
  r.deq:push(val); if r.aw then M.notify(r.aw) end
end
M.Send.__call = M.Send.send
M.Send.__len = function(send)
  local r = send._recv; return r and #r or 0
end

M.channel = mt.doc[[
channel() -> Send, Recv: helper to open sender and receiver.
]](function() local r = M.Recv(); return r, r:sender() end)

----------------------------------
-- singleExecuteLoop(ex): handle a single execute loop
M.singleExecuteLoop = function(ex)
  local waiting = false
  if not ds.isEmpty(ex.ready) then
    local ready = ex.ready; ex.ready = {}
    for sch in pairs(ready) do execute(ex, sch) end
  end

  -- Execute coroutines that need sleeping/polling
  local mh = ex.monoHeap; local hpop = mh.pop
  local now, till = ex:mono()
  if #ex.ready > 0 then till = now -- no sleep when there are ready
  else                  till = now + ex.defaultSleep end
  while true do -- handle mono (sleep)
    -- keep popping from the minheap until it is before 'now'
    local e = hpop(mh); if not e then break end
    if e[1] > now then
      mh:add(e); till = math.min(till, e[1])
      break
    end
    ex.ready[e[2]] = true -- e[2] == Scheduled
  end

  -- done: we move any isDone Scheduled to ready
  local i, done = 1, ex.done
  while i <= #done do
    local sch = done[i]
    if sch.aw:isDone() then
      ex.ready[sch] = true; ds.popit(done, i)
    else i = i + 1 end
  end

  local duration = till - now
  if duration < ds.DURATION_ZERO then duration = ds.DURATION_ZERO end
  local pl, pm = ex.pollList, ex.pollMap
  -- TODO: sleep if #pl==0
  for _, fileno in ipairs(pl:ready(duration)) do
    ex.ready[ds.popk(pm, fileno)] = true; pl:remove(fileno)
  end
end

return M
