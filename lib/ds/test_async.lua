METATY_CHECK = true

local pkg = require'pkg'
local mty = pkg'metaty'

local test, assertEq, assertErrorPat; pkg.auto'civtest'

local ds = pkg.auto'ds'
local da = pkg'ds.async'
local push, yield = table.insert, coroutine.yield

test('async.schedule', function()
  ASYNC_EXECUTOR = da.Executor()

  local sch = da.schedule(function()
    yield(da.ready())
    return 'done'
  end)
  assertEq({awaitKind='ready'}, sch.aw)
  assertEq('thread', type(sch.cor))
  local ok, result = coroutine.resume(sch.cor); assert(ok)
  assertEq({awaitKind='ready'}, result)
  local ok, result = coroutine.resume(sch.cor); assert(ok)
  assertEq('done', result)

  ASYNC_EXECUTOR = nil
end)

test('ch', function()
  local ex = da.Executor()
  ASYNC_EXECUTOR = ex

  local r, s = da.channel(); assert(r and s)
  local deq = r.deq
  local cor = coroutine.create(function()
    while true do
      yield(r())
    end
  end)
  local function nxt(cor)
    return select(2, coroutine.resume(cor))
  end
  local aw = nxt(cor)
  assertEq(da.listen(), aw)
  assertEq(#r, 0); assertEq(false, r:isDone())

  s'first'; assertEq(1, #r); assertEq(1, deq.right); assertEq(1, deq.left)
  assertEq('first', nxt(cor))
  assertEq(0, #r)
    assertEq(1, deq.right); assertEq(2, deq.left)
    assertEq(da.listen(), nxt(cor))
    assertEq(1, deq.right); assertEq(2, deq.left)

  s'second'; s'third'
  assertEq(2, #r); assertEq(3, deq.right); assertEq(2, deq.left)

  assertEq('second', r())
  assertEq(false, r:isDone())
  assertEq(false, s:isClosed())
  s:close(); assertEq(false, r:isDone())
  assertEq(true, s:isClosed())

  assertEq('third', r())
  assertEq(true, r:isDone())
  assertEq(nil, r())

  s = r:sender(); assertEq(false, r:isDone())
  s'fourth'; assertEq('fourth', r())
  assertEq(false, r:isDone()); r:close(); assert(r:isDone());
  assert(s:isClosed()); assert(r:isClosed())


  r = da.Recv(); do
    local s1 = r:sender(); assertEq(false, r:isDone())
    s1:send'inner'
  end; collectgarbage()
  cor = coroutine.create(function()
    while true do
      yield(r())
    end
  end)
  assertEq('inner', nxt(cor)); assertEq(true, r:isDone())

  print('!! playing with executor')
  s = r:sender() -- there is a sender, so nxt MIGHT return a value
  aw = nxt(cor); assertEq(da.listen(), aw)
                 assert(aw == r.aw)
  local sch = da.Scheduled{aw=aw, cor=cor}
  da.EX_UPDATE.listen(ex, sch) -- what the executeLoop does
  s:close(); -- calls notify(r.aw)
  assert(ex.ready[sch]); ex.ready[sch] = nil
  do
    local r1 = da.Recv(); s = r1:sender()
    s'unused'; assertEq(1, #r1)
    assertEq(false, s:isClosed())
  end; collectgarbage()
  assert(s:isClosed())

  ASYNC_EXECUTOR = nil
end)

test('executeLoop', function()
  local ex = da.Executor()
  local monoTime; ex.mono = function() return monoTime end
  monoTime = ds.Duration(5, 0); assertEq(5, ex:mono():asSeconds())
  monoTime = ds.Duration(7, 0); assertEq(7, ex:mono():asSeconds())

  ex.pollList = {ready=function() return {} end}

  ASYNC_EXECUTOR = ex
  local out = 5
  da.schedule(function() out = out * 3 end); assertEq(5, out)
  da._executeLoop(ex, ex.ready); assertEq(15, out)

  local isDone = false
  assert(ds.isEmpty(ex.ready))
  da.schedule(function()
    out = 21; yield(da.ready())
    out = 22; yield(da.done(function() return isDone end))
    out = 23; yield(da.mono(ds.Duration(9)))
    out = 99
  end)
  assert(not ds.isEmpty(ex.ready))
  print('!! Executing multi yield')
  assertEq(15, out)
  da._executeLoop(ex); assertEq(21, out)
  da._executeLoop(ex); assertEq(22, out); assertEq(1, #ex.done)
  for _=1,10 do -- requires isDone=true
    da._executeLoop(ex); assertEq(22, out)
  end
  isDone = true
  da._executeLoop(ex); assertEq(22, out) -- moves done -> ready
  da._executeLoop(ex); assertEq(23, out)
  assertEq(1, #ex.monoHeap)
  assertEq(ds.Duration(9), ex.monoHeap[1][1])

  for _=1,10 do -- requires monotime increase
    da._executeLoop(ex); assertEq(23, out)
  end; assertEq(ds.Duration(9), ex.monoHeap[1][1])

  assert(ds.isEmpty(ex.ready))
  monoTime = ds.Duration(9.1)

  da._executeLoop(ex); assertEq(23, out)
  assertEq(0, #ex.monoHeap)
  assert(not ds.isEmpty(ex.ready))

  da._executeLoop(ex); assertEq(99, out)
  ASYNC_EXECUTOR = nil
end)
