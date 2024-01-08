METATY_CHECK = true

local mty = require'metaty'
local push = table.insert

local test, assertEq, assertErrorPat; mty.lrequire'civtest'

local min, max, bound, isWithin, sort2, decAbs
local indexOf, copy, deepcopy
local strInsert, strDivide, trim
local steal, getOrSet, getPath, setPath, drain, reverse
local eval
local Set, LL, Duration, Epoch
local lines
local M = mty.lrequire'ds'
local df = require'ds.file'

test('bool and none', function()
  local none = M.none
  assertEq(false, M.bool())
  assertEq(false, M.bool(false))
  assertEq(false, M.bool(none))
  assertEq(true, M.bool(true))
  assertEq(true, M.bool(''))
  assertEq(true, M.bool(0))
  assertEq(true, M.bool({}))
  assert(none) -- truthy, use ds.bool for falsy
  assert(rawequal(none, none))
  assert(none == none)
  assertEq(none, none)
  assert(none ~= {})
  assert(not mty.eq(none, {}))
  assertEq('none', getmetatable(none))
  assertEq('none', mty.ty(none))
  assertEq('none', mty.fmt(none))
  local err = 'invalid operation on sentinel'
  assertErrorPat(err, function() none.foo = 3 end)
  assertErrorPat(err, function() return #none end)
end)

test("number", function()
  assert(0, decAbs(1)); assert(0, decAbs(-1))

  assert(1 == min(1, 3)); assert(-1 == min(1, -1))
  assert(3 == max(1, 3)); assert(1  == max(1, -1))
  assert(1 == bound(0, 1, 5))
  assert(1 == bound(-1, 1, 5))
  assert(3 == bound(3, 1, 5))
  assert(5 == bound(7, 1, 5))
  assert(5 == bound(5, 1, 5))
  assert(    isWithin(1, 1, 5))
  assert(not isWithin(0, 1, 5))
  assert(    isWithin(3, 1, 5))
  assert(    isWithin(5, 1, 5))
  assert(not isWithin(6, 1, 5))

  local a, b = sort2(1, 2); assert(a == 1); assert(b == 2)
  local a, b = sort2(2, 1); assert(a == 1); assert(b == 2)
end)

test("str", function()
  assertEq("12 34 56", strInsert("1256", 3, " 34 "))
  assertEq("78 1256", strInsert("1256", 1, "78 "))
  assertEq("1256 78", strInsert("1256", 5, " 78"))
  local a, b = strDivide('12345', 3)
  assertEq(a, '123'); assertEq(b, '45')

  assertEq('hi there', trim('  hi there\n '))
  assertEq('hi there', trim('hi there'))
  local multi = [[  one

three
four

]]
  assertEq('  one\n\nthree\nfour\n\n', multi)
  assertEq('one\n\nthree\nfour', trim(multi))

  assertEq([['hello']], M.q1str[[hello]])
  assertEq([['\'hello\'']], M.q1str[['hello']])
  assertEq([['"hello"']], M.q1str[["hello"]])
end)

test("table", function()
  local t1, t2 = {1, 2}, {3, 4}
  assert(1 == indexOf(t2, 3)); assert(2 == indexOf(t2, 4))

  t1.a = t2
  local r = deepcopy(t1)
  assert(r[1] == 1)
  assert(r.a[1] == 3)
  t2[1] = 8
  assert(r.a[1] == 3)

  local t = {a=8, b=9}
  assert(8 == steal(t, 'a')) assert(9 == steal(t, 'b'))
  assert(0 == #t)

  assertEq(5,   getOrSet({a=5}, 'a', function() return 7 end))
  assertEq(7,   getOrSet({b=5}, 'a', function() return 7 end))
  assertEq(7,   getPath({a={b=7}}, {'a', 'b'}))
  assertEq(nil, getPath({}, {'a', 'b'}))
  assertEq(nil, getPath({}, {'a', 'b'}))

  local t = {}
  setPath(t, {'a', 'b'}, 4); assertEq(4, t.a.b)
  setPath(t, {'a', 'a', 'a'}, 5);   assertEq(5, t.a.a.a)
  setPath(t, {'a', 'a', 'a'}, nil); assertEq(nil, t.a.a.a)
  setPath(t, {'a', 'b'}, 4); assertEq(4, t.a.b)

  t = {}; for i, v in M.inext, {4, 5, 8}, 0 do t[i] = v end
  assertEq({4, 5, 8}, t)
  t = {}; for i, v in M.iprev, {4, 5, 8}, 4 do t[i] = v end
  assertEq({4, 5, 8}, t)
  t = {}; for i, v in M.ireverse{4, 5, 8} do t[i] = v end
  assertEq({4, 5, 8}, t)

  t = {}; for i, v in M.islice({5, 6, 7, 8, 9}, 2, 4) do
    push(t, v)
  end
  assertEq({6, 7, 8}, t)


  t = {}
  M.walk(
    {1, 2, a=3, inner={b=9, c='hi'}},
    function(k, v) t[k] = v end,
    function(k, v) t[k] = true end)
  assertEq({1, 2, a=3, b=9, c='hi', inner=true}, t)
end)

test('list', function()
  local l = {'a', 'b', 'c', 1, 2, 3}
  assertEq({1, 2, 3}, drain(l, 3))
  assertEq({'a', 'b', 'c'}, l)
  assertEq({}, drain(l, 0))
  assertEq({'a', 'b', 'c'}, l)
  assertEq({'c'}, drain(l, 1))
  assertEq({'a', 'b'}, l)
  assertEq({'a', 'b'}, drain(l, 7))
  assertEq({}, l)

  assertEq({2, 1},    reverse({1, 2}))
  assertEq({3, 2, 1}, reverse({1, 2, 3}))
end)

test("eval", function()
  local env = {}
  local ok, err = eval('1+', env)
  assert(not ok); assert(err)
  local ok, three = eval('return 3', env)
  assert(ok); assertEq({}, env)
  assertEq(3, three)
  local ok, three = eval('seven = 7', env)
  assert(ok); assertEq({seven=7}, env)
  assert(not seven) -- did not modify globals
end)

test('Set', function()
  local s = Set{'a', 'b', 'c'}
  assertEq(Set{'a', 'c', 'b'}, s)
  assertEq(Set{'a', 'b'}, s:union(Set{'a', 'b', 'z'}))
  assertEq(Set{'a'}, s:diff(Set{'b', 'c', 'z'}))
end)

test('LL', function()
  local ll = LL(); assert(ll:isEmpty())
  ll:addFront(42); assertEq(42, ll:popBack())
  ll:addFront(46); assertEq(46, ll:popBack())
  assert(ll:isEmpty())
  ll:addFront(42):addFront(46);
  assertEq(46, ll.front.v);         assertEq(42, ll.back.v)
  assertEq(ll.front, ll.back.prv); assertEq(ll.back, ll.front.nxt)
  assertEq(nil, ll.front.prv);     assertEq(nil, ll.back.nxt)
  assertEq(42, ll:popBack()) assertEq(46, ll:popBack())
  assert(ll:isEmpty())
  assertEq(nil, ll:popBack())
  ll:addFront(42):addFront(46):addBack(41)
  assertEq(41, ll.back.v); assertEq(46, ll.front.v)
  assertEq(42, ll.front.nxt.v);  assertEq(42, ll.back.prv.v);
  assertEq(46, ll:popFront())
  assertEq(42, ll.front.v); assertEq(41, ll.back.v)
  assertEq(ll.front.nxt, ll.back)
end)

test('time', function()
  local N = Duration.NANO
  local d = Duration(3, 500)
  assertEq(Duration(2, 500),     Duration(3, 500) - Duration(1))
  assertEq(Duration(2, N - 900), Duration(3, 0)   - Duration(0, 900))
  assertEq(Duration(2, N - 800), Duration(3, 100) - Duration(0, 900))
  assertEq(Duration(2), Duration:fromMs(2000))
  assert(Duration(2) < Duration(3))
  assert(Duration(2) < Duration(2, 100))
  assert(not (Duration(2) < Duration(2)))
  assertEq(Duration(1.5), Duration(1, N * 0.5))
  assertEq('1.5s', tostring(Duration(1.5)))

  assertEq(Epoch(1) - Duration(1), Epoch(0))
  assertEq(Epoch(1) - Epoch(0), Duration(1))
  local e =    Epoch(1000001, 12342)
  assertEq(e - Epoch(1000000, 12342), Duration(1))
  assertEq('Epoch(1.5s)', tostring(Epoch(1.5)))
end)

test('lines.sub', function()
  local lsub = lines.sub
  local l = lines'ab\nc\n\nd'
  assertEq({'ab'},      lsub(l, 1, 1))
  assertEq({'ab', 'c'}, lsub(l, 1, 2))
  assertEq({'c', ''},   lsub(l, 2, 3))
  assertEq('ab\n',      lsub(l, 1, 1, 1, 3))
  assertEq('ab\n',      lsub(l, 1, 1, 2, 0))
  assertEq('b\nc',      lsub(l, 1, 2, 2, 1))

  l = lines"4     It's nice to have some real data"
  assertEq('It',     lsub(l, 1, 7, 1, 8))
  assertEq("'",      lsub(l, 1, 9, 1, 9))
  assertEq("s",      lsub(l, 1, 10, 1, 10))
  assertEq(" nice",  lsub(l, 1, 11, 1, 15))
end)

test('path', function()
  local pc = M.path.concat
  assertEq('foo/bar',   pc{'foo/', 'bar'})
  assertEq('/foo/bar',  pc{'/foo/', 'bar'})
  assertEq('/foo/bar/', pc{'/foo/', 'bar/'})
  assertEq('',          pc{''})
  assertEq('a/b',       pc{'a', '', 'b'})

  local pf = M.path.first
  assertEq({'/',  'a/b/c/'}, {pf'/a/b/c/'})
  assertEq({'a',  'b/c/'},   {pf'a/b/c/'})
  assertEq({'/',  'a/b/'},   {pf'/a/b/'})
  assertEq({'/',  'a/b'},    {pf'/a/b'})
  assertEq({'/',  'b'},      {pf'/b'})
  assertEq({'b',  ''},       {pf'b'})
  assertEq({'/',  'b/'},     {pf'/b/'})
  assertEq({'/',  ''},       {pf'/'})

  local pl = M.path.last
  assertEq({'/a/b', 'c/'}, {pl'/a/b/c/'})
  assertEq({'a/b', 'c/'},  {pl'a/b/c/'})
  assertEq({'/a', 'b/'},   {pl'/a/b/'})
  assertEq({'/a', 'b'},    {pl'/a/b'})
  assertEq({'', '/b'},     {pl'/b'})
  assertEq({'', 'b'},      {pl'b'})
  assertEq({'', '/b/'},    {pl'/b/'})
  assertEq({'', '/'},      {pl'/'})
end)

test('Imm', function()
  local t = M.Imm{1, 2, v=3}
  assertEq(1, t[1])
  assertEq(3, t.v)
  assertEq('table', getmetatable(t))
  assertEq('table', mty.ty(t))
  assertErrorPat('set on immutable', function() t.b = 8 end)
  assertErrorPat('set on immutable', function() t.v = 8 end)
  local j = M.Imm{1, 2, v=3}
  local k = M.Imm{1, 2, v=4}
  assert(t == t); assert(t ~= j)
  assertEq(t, t); assertEq(t, j)
  assert(t ~= k); assert(not mty.eq(t, k))
  assertEq('{1 :: k=5}', mty.fmt(M.Imm{1, k=5}))
  assertEq('table', mty.tyName(M.Imm{}))

  assertEq({1, 2, v=3}, j) -- table vs Imm
  assert(not mty.eq({1, 2}, j))

  assertEq({kind='Empty'}, M.Imm{kind='Empty'})
end)

local heap = require'ds.heap'

local function pushh(h, t)
  for i, v in ipairs(t) do h:add(v) end
end

local function assertPops(expect, h)
  local t = {}; while #h > 0 do
    push(t, h:pop())
  end
  assertEq(expect, t)
end
test('heap', function()
  local h = heap.Heap{1, 5, 9, 10, 3, 2}
  assertPops({1, 2, 3, 5, 9, 10}, h)
  assertEq(0, #h)
  pushh(h, {8, 111, -1, 333, 42})
  assertEq(heap.Heap{-1, 42, 8, 333, 111}, h)
  assertPops({-1, 8, 42, 111, 333}, h)

  h = heap.Heap({1, 5, 9, 10, 3, 2}, M.gt)
  assertPops({10, 9, 5, 3, 2, 1}, h)
end)

test('dag', function()
  local childrenMap = {
    a = {'b', 'c'},
    b = {'c', 'd'},
    c = {'d'}, d = {},
  }
  local parentsMap = M.dag.reverseMap(childrenMap)
  for _, v in pairs(parentsMap) do table.sort(v) end
  assertEq({
    d = {'b', 'c'}, c = {'a', 'b'},
    b = {'a'},      a = {},
  }, parentsMap)

  local result = M.dag.reverseMap(parentsMap)
  for _, v in pairs(result) do table.sort(v) end
  assertEq(childrenMap, result)

  assertEq({'d', 'c', 'b', 'a'}, M.dag.sort(childrenMap))
end)

test('LinesFile_small', function()
  assertEq(5, df.readLen'testdata/small.txt')
  local f = io.open('testdata/small.txt')
  assertEq(5, df.readLen(f)); f:seek'set'

  local lf = df.LinesFile{f, cache=2}
  assertEq('This is a small file', lf[1])
  assertEq('it is for testing.',   lf[2])
  assertEq('',                     lf[3])
  assertEq(0, lf.cacheMiss)
  assertEq('This is a small file', lf[1])
  assertEq(1, lf.cacheMiss)
  assertEq(nil, rawget(lf, 2))
  assertEq('it is for testing.',   lf[2])
  assertEq(1, lf.cacheMiss)

  assertEq('',                     lf[5])
  assertEq('It ends in a newline', lf[4])
  assertEq(1, lf.cacheMiss)

  assertEq(math.maxinteger, lf.len)
  assertEq(nil,             lf[6])
  assertEq(5,               lf.len)
  assertEq(nil,             lf[7])
  assertEq(5,               lf.len)
end)

test('LinesFile_append', function()
  local fname = os.tmpname()
  local lf = df.LinesFile:appendTo{fname, cache=3}
  lf[1] = 'first line'
  lf[2] = 'second line'
  lf:flush()
  assertEq('first line',  lf[1])
  assertEq('second line', lf[2])
  lf[3] = 'third line'
  lf:flush()
  assertEq('second line', lf[2])
  assertEq('third line',  lf[3])
  assertEq(3,             #lf)
  lf.file:seek'set'
  assertEq([[
first line
second line
third line
]], lf.file:read'a')
end)

test('IndexedFile_append', function()
  local f = io.tmpfile()
  local orig = [[
hi there
this file

is indexed
for speed.
]]
  f:write(orig)
  local fx = df.IndexedFile{f}
  local idxf = fx.idx.file
  idxf:flush()
  assertEq(0,  fx.idx:getPos(1))
  assertEq(9,  fx.idx:getPos(2))
  assertEq(0,  fx.idx:getPos(1))
  assertEq(19, fx.idx:getPos(3))
  assertEq('hi there',   fx[1])
  assertEq('this file',  fx[2])
  assertEq('',           fx[3])
  assertEq('is indexed', fx[4])
  assertEq('for speed.', fx[5])
  assertEq(nil,          fx[0])
  assertEq(nil,          fx[6])

  assertEq({'hi there', 'this file', ''}, lines.sub(fx, 1, 3))
  assertEq('there\nthis file\n', lines.sub(fx, 1, 4, 3, 0))

  local appended = 'and can be appended to'
  fx[6] = appended
  fx:flush()
  assertEq(appended, fx[6])
  f:seek'set'
  assertEq(orig..appended..'\n', f:read'a')
end)
