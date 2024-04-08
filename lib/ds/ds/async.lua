
local pkg = require'pkg'
local mt  = pkg'metaty'
local ds  = pkg'ds'
local heap = pkg'ds.heap'

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

M.getCor    = function(aw) return aw[0]  end
M.getParent = function(aw) return aw[-1] end

local function _await(aw, awaitKind)
  aw.awaitKind = awaitKind
  return aw
end

local IMM_POLITE = ds.Imm{awaitKind='polite'}
M.polite = mt.doc[[
polite() -> Await{kind=polite}
Await until next loop. Prevents any sleeps.

Note: it is called "polite" since the coroutine is being polite by yielding
  during it's work. It's also a pun since it allows "polite poll-ing".
]](function() return IMM_POLITE end)

M.done = mt.doc[[
done(isDoneFn) -> Await{kind=done}
Await until isDone() returns true.

Note: the loop may still sleep for up to it's defaultSleep amount.
]](function(isDoneFn)
  assert(ds.callable(isDoneFn), 'isDoneFn must be callable')
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

M.poll = mt.doc[[poll(pollTable, parent) -> Await{kind=poll}
When yielded to an executeLoop, restart the coroutine after the system's
poll(...). Returns it as a valid fileid. The specific implementation depends on
the Executor.
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
  :fieldMaybe'children':fdoc'table of children (keys=Scheduled) and .count'
  :fieldMaybe'finished':fdoc'list of finished (removed) children in order'


M.schedule = mt.doc[[
schedule(fn, Ex=defaultGlobalExecutor) -> Scheduled
Schedule fn on the Executor. The scheduled coroutine will be run
on the next loop (this function returns without resuming it).

Note: converts fn to a coroutine if it is not already type=="thread".
]](function(fn, ex)
  ex = ex or M.globalExecutor; assert(ex, "must provide executor")
  if type(fn) == 'function' then fn = coroutine.create(fn) end
  assert(type(fn) == 'thread', 'can only schedule a fn or coroutine')
  local sch = M.Scheduled{aw=IMM_POLITE, cor=fn}
  ex.ready[sch] = true
  return sch
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
  are lists of Scheduled instances to execute with Await instances of
  the named types.
    polite    done    any    all

  These are a slightly different type. The default is still an empty instance:
    monoHeap       ds.heap.Heap (minheap) of {Duration, Scheduled}
    pollMap        table of fileno -> Scheduled

  pollList is special and may only be supported on some platforms (else nil).
  It must have the following methods:
    insert(fileno, events) insert the fileno+events into the poll list
    remove(fileno)         remove the fileno from poll list
    len()     -> integer   return the total number of filenos
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
-- finish(Scheduled, Executor=defaultGlobal)
-- Finish the Scheduled instance.
-- Clears fields of Sch and notifies parents of completion, moving the parents
-- to the Executor if they are ready.
local function finish(sch, ex)
  ex = ex or M.globalExecutor; assert(ex, "must provide executor")
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
  polite = function(ex, sch) ex.ready[sch] = true end,
  done   = function(ex, sch) push(ex.done, sch) end,
  mono   = function(ex, sch) ex.mono:add{assert(sch.aw.mono), sch} end,
  poll   = function(ex, sch)
    local aw = sch
    ex.pollList:insert(aw.fileno, aw.events)
    ex.pollMap[aw.fileno] = sch
  end,
  any = updateAnyAll, all = updateAnyAll,
}

-- execute(scheduled, ex) -> isDone, error
--
-- Execute (coroutine.resume) the scheduled item, updating the Executor and any
-- parents depending on result. isDone is returned if the item is done.
local function execute(ex, sch)
  local cor = sch.cor
  if not cor then M.finish(sch, ex); return true     end -- no coroutine
  local ok, aw = coroutine.resume(cor)
  if not ok  then M.finish(sch, ex);  return true, aw end -- error
  if not aw  then M.finish(sch, ex);  return true     end -- isDone
  sch.aw = aw; EX_UPDATE[aw.awaitKind](ex, sch)
end

----------------------------------
-- executeLoop(ex): default executeLoop implementation for main

local function _ready(isReadyFn, ready, ex, schs)
  local popit = ds.popit
  local i = 1; while true do
    local len = #schs; if i > len then break end
    if isReadyFn(schs[i]) then
      push(ready,  popit(schs, i))
    else i = i + 1 end
  end
end

M.executeLoop = mt.doc[[
executeLoop(ex) -> (): default executeLoop suitable for most applications.
]](function(ex)
  local resume, popit, popk = coroutine.resume, ds.popit, ds.popk
  local defaultSleep = ex.defaultSleep or Duration:fromMs(5)
  local now, till, i, ready, done, sch, aw, err

  ready = ex.ready; ex.ready = {}
  while true do
    -- done: we move any isDone Scheduled to ready
    done = ex.done; i = 1; while i <= #done do
      sch = done[i]
      if sch.aw:isDone() then
        popit(done, i)
        ex.ready[sch] = true
      else i = i + 1 end
    end

    -- Execute all ready coroutines. This will update
    -- executor fields.
    for sch in pairs(ready) do execute(ex, sch) end
    ready = ex.ready; ex.ready = {}

    -- Execute coroutines that need sleeping/polling
    now = ex:mono()
    local mh = ex.monoHeap; local hpop = mh.pop
    if #ready > 0 then till = now -- no sleep when there are ready
    else               till = now + defaultSleep end
    while true do -- handle mono (sleep)
      -- keep popping from the minheap until it is before 'now'
      local e = hpop(mh); if not e then break end
      if e[1] > now then
        mh:add(e); till = math.min(till, e[1])
        break
      end
      ready[e[2]] = true -- e[2] == Schedule
    end

    local duration = till - now
    if duration < ds.DURATION_ZERO then duration = ds.DURATION_ZERO end
    local pl, pm = ex.pollList, ex.pollMap
    for _, fileno in ipairs(pl:ready()) do
      ready[popk(pm, fileno)] = true; pl:remove(fileno)
    end
  end
end)

return M
