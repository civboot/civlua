
local pkg = require'pkg'
local mt  = pkg'metaty'
local ds  = ds.noop
local heap = ds.heap

local push, pop = table.insert, table.remove
local sfmt = string.format
local resume, newcor = coroutine.resume, coroutine.create

local M = mt.docTy({}, [[
Enables writing simple "blocking style" lua then running asynchronously
with standard lua coroutines.

This library is pure lua. The only C code required is to create non-blocking
versions of system-level objects like files/etc (not part of this module). In
many cases, this architecture can be used with already written Lua code written
in a "blocking" style.

## Architecture
This library provides "types" for communicating with the executeLoop as well as
a default implementation of the executeLoop. The basic design is that when Lua
is in "async mode" the blocking APIs (i.e. print, open, read, etc) are replaced
with versions which `yield someAwait(...)` instead of 
`return someBlockingCall()`. The executeLoop() will then properly handle this
value and call the coroutine when it is again ready.

Most code will continue to use `io.open()` and `file:read()` normally, but
these APIs will yield instead of blocking and the types (i.e. `file`) will be
slightly different when in async mode.

This is achieved by three separate libraries:
* ds.async (this library) which provides standard types/interfaces/functions
* civix (or an equivalent) which provides file/etc types that support truly
  non-blocking filedescriptors (i.e. pipes/sockets) as well as normally blocking
  filedescriptors (i.e. a file) backed by a thread.
* a future library which enables libraries like civix to register themselves
  and which perform the actual replacement of functions (i.e. replaces
  the global `print` as well as `io.open` etc with non-blocking equivalents).


## ds.async API

Create Await instance of kind = (polite  done  mono  poll  any  all)
  The specific requirements differs for each await kind (see documentation in
  function named same thing) However, they all have the 'stop' field. When set,
  the stop field will cause the coroutine to be stopped the next time it would
  have otherwise been run.

Interact with Await instance:
  checkAwait  isReady

Executor (see function docs)
  Executor  checkExecutor

Other functions (see individual documentation)
  schedule  executeLoop

Global variables:
  ds.async.globalExecutor: used as default executor in ds.async functions
]])


----------------------------------
-- Await instance creation
-- These aren't real "types" as they don't have a metatable.
-- However, they DO all have the field 'awaitKind'.
local IMM_IMMEDIATE = ds.Imm{awaitKind='polite'}
M.polite = mt.doc[[
polite(parent) -> Await{kind=polite}
When yielded to an executeLoop, rerun coroutine immediately on next loop since
there is immediate work to do. Prevents any sleeps.

Note: it is called "polite" since the coroutine is being polite by yielding
  during it's work. It's also a pun since it allows "polite poll-ing".
]](function(parent)
  if parent then return {awaitKind='polite', parent=parent}
  else return IMM_IMMEDIATE end
end)

M.done = mt.doc[[
done(isDoneFn, parent) -> Await{kind=done}
When yielded to an executeLoop, restart coroutine when isDone() returns true.

Note: the loop may still sleep for up to it's defaultSleep amount.
]](function(isDoneFn, parent)
  assert(ds.callable(isDoneFn), 'isDoneFn must be callable')
  return {awaitKind='done', isDone=isDoneFn, parent=parent}
end)

M.mono = mt.doc[[
mono(monoDuration, parent) -> Await{kind=mono}
Resart coroutine sometime after the system monotomic timer >= monoDuration.
Affects the maximum length of loop sleep.
]](function(mono, parent)
  assert(mt.ty(mono) == ds.Duration, 'first arg must be duration type')
  return {awaitKind='mono', mono=mono, parent=parent}
end)

M.poll = mt.doc[[poll(fileno, events, parent) -> Await{kind=poll}
When yielded to an executeLoop, restart the coroutine after the system's
poll(fileno, events) returns it as a valid fileid. The specific implementation
depends on the Executor.
]](function(fileno, events, parent)
  return {awaitKind='poll', fileno=fileno, events=events}
end)

-- Implementation for any() and all()
local anyAll = function(name, ex, fns) --> awaits, cors
  local out, awaits, cors, fin = {}, {}, {}, {}
  local create = coroutine.create
  for i, cor in ipairs(fns) do
    cor = (type(cor) == 'thread') and cor or create(cor)
    local ok, aw = resume(cor);
    if not ok then
      for _, cor in ipairs(cors) do coroutine.close(cor) end
      mt.errorf('%s(fns) index=%s failed: %s',
        name, i, ds.coroutineErrorMessage(cor, aw))
    end
    if aw then
      aw.parent = out
      push(awaits, aw); push(cors, cor)
    else -- finished immediately
      assert(coroutine.close(cor));
      push(awaits, false); push(cors, false); push(fin, i);
    end
  end
  for i, aw in ipairs(awaits) do if aw then
      M.EX_UPDATE[aw.awaitKind](ex, aw, cors[i])
  end end
  out.awaits = awaits; out.coroutines = cors; out.finished = fin
  return out
end

M.any = mt.doc[[
any(ex, fns, parent) -> Await{kind=any}
Schedule the fns (or coroutines) on the given executor. When yielded to an
executeLoop, rerun yielding coroutine when ANY of the fns complete.

The returned Await instance has the following fields:
  awaits      a list of Await instances AND instance->index map.
  coroutines  a list of coroutines coresponding to the await instances
  finished    a list of indexes that have finished.
  lastLen     integer for executorLoop to compare with #finished

The calling process MAY cache `lastLen` and use the indexes in `finished` to
determine the next course of action -- or it may use closures or other
shared state to communicate with the sub-processes.

Warning: do NOT modify any of these fields in the yielding coroutine. Doing so
  may result in undefined behavior in the executorLoop. They can be read.

Error: if any of the fns don't complete their first resume, which is required
  to obtain an Await instance for them
]](function(ex, fns, parent)
  local aw = anyAll('any', ex, fns)
  aw.lastLen = #aw.finished; aw.parent = parent
  return aw
end)

M.all = mt.doc[[
all(ex, fns, parent) -> Await{kind=all}
Schedule the fns or coroutines on the given executor. When yielded to an
executeLoop, retrun coroutine when ALL of the fns complete.

This has the same fields as any() except for 'lastLen'. However, it's
  fields are less commonly inspected as it is only finished when every
  sub-coroutine is completed.

Error: on first fn that doesn't complete the first resume, which is required to
  obtain an Await instance for it.
]]
(function(ex, fns, parent)
  local aw = anyAll('all', ex, fns); aw.parent = parent
  return aw
end)

M.stop = mt.doc[[
stop(await) -> ()
Signal to the executeLoop to stop the coroutine the next time it
would be run.
]](function(aw) aw.stop = true end)

M.shouldStop = function(aw)
  return aw.stop or (aw.parent and aw.parent.stop)
end

M.handleErrorDefault = function(err, aw, cor)
  error(ds.coroutineErrorMessage(cor, err), 2)
end

local checkAnyAll = function(aw)
  local t = ' must be a table'
  if type(aw.awaits)     ~= 'table'        then
    return 'aw.awaits must be a table'     end
  if type(aw.coroutines) ~= 'table'        then
    return 'aw.coroutines must be a table' end
  if type(aw.finished)   ~= 'table'        then
    return 'aw.finished must be a table'   end
end
local AW_CHECK = {
  polite = ds.retFalse, -- no further requirements
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
    return 'aw must have string field awaitKind'
  end
  local fn = AW_CHECK[aw.awaitKind]
  if not fn then return sfmt(
    'aw.awaitKind is not a recognized kind: %s', aw.awaitKind
  )end
  return fn(aw)
end)

local AW_READY = {
  polite = ds.retTrue, -- always ready
  done   = function(ex, aw) return aw:isDone()                end,
  mono   = function(ex, aw) return ex:mono() >= aw.mono       end,
  poll   = function(ex, aw) return ex:pollSingle(aw, 0)       end,
  any    = function(ex, aw) return #aw.finished > aw.lastLen  end,
  all    = function(ex, aw) return #aw.finished >= #aw.awaits end,
}
M.isReady(aw, ex) = mty.doc[[
isReady(await, ex=ds.await.globalExecutor) -> boolean
Using the executor, returns whether the Await instance is ready.
]](function(aw, ex)
  ex = ex or M.globalExecutor; assert(ex, "must provide executor")
  return AW_READY[aw.awaitKind](ex, aw)
end)

----------------------------------
-- Executor{} and schedule()
M.globalExecutor = false -- set for global executor
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
  are lists coresponding to the awaitKind. The indexes of the '*Awaits'
  must be kept insync with the '*Cors' (aka coroutines).
               doneAwaits    anyAwaits    allAwaits
     polite    doneCors      anyCors      allCors

  These are a slightly different type. The default is still an empty instance:
    -- these all have a default of being empty
    monoHeap       : ds.heap.Heap (minheap) of {Duration, Await, cor}
    pollMapAwaits  : table of fileno -> Await
    pollMapCors    : table of fileno -> coroutine

  pollList is special and may only be supported on some platforms (else nil).
  It must have the following methods:
    insert(fileno, events) insert the fileno+events into the poll list
    remove(fileno)         remove the fileno from poll list
    len()     -> integer   return the total number of filenos
]](function(ex)
  ex = ex or {}
  for _, f in ipairs {
    'monoHeap', 'pollMapAwaits', 'pollMapCors', 
                'doneAwaits', 'anyAwaits', 'allAwaits',
    'polite',   'doneCors',   'anyCors',   'allCors',
  } do ds.getOrSet(ex, f, ds.newTable) end
  if mt.ty(ex.monoHeap) ~= heap.Heap then
    ex.monoHeap.cmp = M.awaitMonoCmp; ex.monoHeap = heap.Heap(ex.monoHeap)
  end
  local eu = M.executorUnsuported
  if not ex.mono        then ex.mono        = eu end
  if not ex.pollAwait   then ex.pollAwait   = eu end
  if not ex.poll        then ex.poll        = eu end
  if not ex.handleError then ex.handleError = M.handleErrorDefault end
  return ex
end)

M.schedule = mt.doc[[
schedule(fn, executor) -> (res, cor)
schedule fn onto the executor (default=ds.async.executor).
This enables cooperative multitasking.

Error: res=nil on error. In this case, the coroutine was NOT scheduled.
  This will happen if the first resume(Fn) call failed.
]](function(cor, ex)
  cor = (type(cor) == 'thread') and cor or coroutine.create(cor)
  ex  = assert(ex or M.defaultExecutor, 'must set an executor')
  local ok, res = resume(cor)
  if not ok then return nil, res end -- error, not scheduled
  M.EX_UPDATE[res.awaitKind](ex, res, cor)
  return res, cor
end)

-- (ex, aw, cor) -> (): update executor with Await and coroutine
M.EX_UPDATE = {
  mono = function(ex, aw, cor)
    ex.mono:add({assert(aw.mono), aw, cor})
  end
  poll = function(ex, aw, cor)
    ex.pollList.insert(aw.fileno, aw.events)
    ex.pollMapAwaits[aw.fileno] = aw
    ex.pollMapCors[aw.fileno]   = cor
  end,
  polite = function(ex, aw, cor)
    push(ex.immAwaits, aw); push(ex.immCors, cor)
  end,
  done = function(ex, aw, cor)
    push(ex.doneAwaits, aw); push(ex.doneCors, cor)
  end,
  any = function(ex, aw, cor)
    push(ex.anyAwaits, aw); push(ex.anyCors, cor)
  end,
  all = function(ex, aw, cor)
    push(ex.allAwaits, aw); push(ex.allCors, cor)
  end,
}

----------------------------------
-- executeLoop(ex): default executeLoop implementation for main
local monoLt = rawget(ds.Duration, '__lt')
M.awaitMonoCmp = function(i1, i2) monoLt(i1[1], i2[1]) end

local function _ready(isReady, readyAws, readyCors, ex, awaits, cors)
  local popit = ds.popit
  local i = 1; while true do
    local len = #awaits; if i > len do break end
    if isReady(awaits[i]) then
      push(readyAws,  popit(awaits, i))
      push(readyCors, popit(cors, i))
    else i = i + 1 end
  end
end

-- res is either error (when ok=false), nil (aka done), or next Await
local function _awFinish(aw, cor)
  assert(coroutine.close(cor))
  local p = aw.parent
  if p then
    push(p.finished, assert(p.awaits[aw]))
    if p.lastLen then p.lastLen = p.lastLen + 1 end
  end
end
local function executeCor(ex, aw, cor)
  local ok, res = resume(cor)
  if not ok or not res then -- finished
    if not ok then ex:handleError(res, aw, cor) end
    _awFinish(aw, cor)
  else M.EX_UPDATE[res.awaitKind](ex, res, cor) end
end

M.executeLoop = mt.doc[[
executeLoop(ex) -> (): default executeLoop suitable for most applications.
]](function(ex)
  local executeCoroutine = M.executeCoroutine
  local resume, popit, popk = coroutine.resume, ds.popit, ds.popk
  local defaultSleep = ex.defaultSleep or Duration:fromMs(5)
  local now, till, i, readyCors, readyAws

  while true do
    readyCors = ex.politeCors; ex.politeCors = {}
    readyAws  = ex.politeAws;  ex.politeAws  = {}

    _ready(AW_READY.done, readyAws, readyCors, ex, ex.doneAwaits, ex.doneCors)
    _ready(AW_READY.any,  readyAws, readyCors, ex, ex.anyAwaits,  ex.anyCors)
    _ready(AW_READY.all,  readyAws, readyCors, ex, ex.allAwaits,  ex.allCors)

    -- Execute ready coroutines
    for i, cor in ipairs(readyCors) do executeCor(ex, readyAws[i], cor) end

    -- Execute coroutines that need sleeping/polling
    readyAws, readyCors = {}, {}
    now = ex:mono()
    local mh = ex.monoHeap; local hpop = mh.pop
    if #ex.politeCors > 0 then till = now -- no sleep when there are polite
    else                       till = now + defaultSleep end
    while true do -- handle mono (sleep)
      -- keep popping from the minheap until it is before 'now'
      local e = hpop(mh); if not e then break end
      if e[1] > now then
        mh:add(e); till = math.min(till, e[1])
        break
      end
      local aw, cor = e[2], e[3]
      local err = M.checkAwait(aw); assert(not err, err)
      assert(type(cor) == 'thread')
      push(readyAws, aw); push(readyCors, cor)
    end

    local duration = till - now
    if duration < ds.DURATION_ZERO then duration = ds.DURATION_ZERO end
    local pl, pmCors, pmAws = ex.pollList, ex.pollMapCors, ex.pollMapAwaits
    for _, fileno in ipairs(pl:ready()) do
      pl:remove(fileno)
      push(readyAws,  popk(pmAws,  fileno))
      push(readyCors, popk(pmCors, fileno))
    end
    for i, cor in ipairs(readyCors) do executeCor(ex, readyAws[i], cor) end
  end
end)

return M
