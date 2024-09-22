METATY_CHECK = true
local function testloc()  return require'ds'.srcloc() end
local function testshort() return require'ds'.shortloc() end
local loc1, loc2 = testloc(), testshort()
local a = function() error'a error' end
local b = function() a() end; local c = function() b() end

local push, yield = table.insert, coroutine.yield
local pop = table.remove
local sfmt = string.format

local mty = require'metaty'
local M, lines = require'ds', require'lines'
local testing = require'lines.testing'

local test, assertEq, assertMatch, assertErrorPat; M.auto'civtest'
local str = mty.tostring

local min, max, bound, isWithin, sort2, decAbs
local indexOf, copy, deepcopy
local trim
local extend, clear, replace, merge
local getOrSet, get, set
local drain, reverse
local eval
local Set, Duration, Epoch
local M = M.auto'ds'
local d8 = require'ds.utf8'
local dp = M.dotpath
local path = require'ds.path'
local s = M.simplestr
local LL = require'ds.LL'

---------------------
-- ds.lua

test('loc', function()
  assertEq('lib/ds/test.lua:4', loc1)
  assertEq('ds/test.lua:4', loc2)

  assertEq(   'lib/ds/',          M.srcdir())
  assertMatch('.*/lib/civtest/$', M.srcdir(1))
  local function fn()
     assertEq(   'lib/ds/',          M.srcdir())
     assertEq(   'lib/ds/',          M.srcdir(1))
     assertMatch('.*/lib/civtest/$', M.srcdir(2))
  end; fn()
end)

test('simplestr', function()
  assertEq('a', [[
a]])
  assertEq('this is\n  a simple str.', s[[
    this is
      a simple str.
  ]])

  assertEq('easy',    s[[easy]])
  assertEq('easy  ',  s[[  easy  ]])
  assertEq('easy\nhi\nthere',  s[[easy
    hi
    there
  ]])
  assertEq('easy',  s[[
  easy
  ]])
end)

test('bool and none', function()
  local none = assert(M.none)
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
  assertEq('none', str(none))
  local err = 'invalid operation on sentinel'
  assertErrorPat(err, function() none.foo = 3 end)
  assertErrorPat(err, function() return #none end)
end)

test('imm', function()
  assertEq({}, M.empty)
  assertEq(nil, next(M.empty))
  assertEq(0,  #M.empty)
  assertEq('table', getmetatable(M.empty))

  local t = M.Imm{1, 2, v=3}
  assertEq(1, t[1])
  assertEq(3, t.v)
  assertEq('table', getmetatable(t))
  assert('table', debug.getmetatable(t).__metatable)
  assertEq('table', mty.ty(t))
  assertErrorPat('cannot modify Imm', function() t.b = 8 end)
  assertErrorPat('cannot modify Imm', function() t.v = 8 end)
  assertEq('<!imm data!>', next(t))
  local j = {1, 2, v=3}
  local k = M.Imm{1, 2, v=4}
  assert(t == t); assert(t ~= j)
  assertEq(t, t)
  assertEq(t, j)

  assert(t ~= k); assert(not mty.eq(t, k))
  assertEq('{1, k=5}', str(M.Imm{1, k=5}))
  assertEq('table', mty.tyName(M.Imm{}))

  assertEq({1, 2, v=3}, j) -- table vs Imm
  assert(not mty.eq({1, 2}, j))

  assertEq({kind='Empty'}, M.Imm{kind='Empty'})
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
  assertEq('hi there', trim('  hi there\n '))
  assertEq('hi there', trim('hi there'))
  local multi = [[  one

three
four

]]
  assertEq('  one\n\nthree\nfour\n\n', multi)
  assertEq('one\n\nthree\nfour', trim(multi))

  assertEq('  a b c', M.trimEnd'  a b c')
  assertEq('  a b c', M.trimEnd'  a b c\n  ')

  assertEq(' a bc d e ', M.squash'  a   bc \td\te ')

  assertEq([['hello']], M.q1str[[hello]])
  assertEq([['\'hello\'']], M.q1str[['hello']])
  assertEq([['"hello"']], M.q1str[["hello"]])

  local u8 = "high🫸 five 🫷!"
  -- test utf8.offset itself
  local off = utf8.offset
  assertEq(4, off(u8, 4))
  assertEq(5, off(u8, 5)) -- start of 🫸
  assertEq(9, off(u8, 6));     assertEq(' five 🫷!', u8:sub(9))
  assertEq(9, off(u8, 1, 9))
  assertEq(19, off(u8, 8, 9)); assertEq('!', u8:sub(19))
  assertEq(2, off('a', 2))

  assertEq("high", M.usub(u8, 1, 4))
  assertEq("🫸 f", M.usub(u8, 5, 7))
  assertEq("🫷!",  M.usub(u8, -2))
  assertEq("e 🫷", M.usub(u8, -4, -2))
  assertEq('',     M.usub(u8, 100))
end)

test('isPod', function()
  assertEq(true,  M.isPod(true))
  assertEq(true,  M.isPod(false))
  assertEq(true,  M.isPod(3))
  assertEq(true,  M.isPod(3.3))
  assertEq(true,  M.isPod'hi')

  assertEq(nil,  M.isPod(M.noop))
  assertEq(nil,  M.isPod(io.open'PKG.lua'))

  assertEq(true, M.isPod{1, 2, a=3})
  assertEq(true, M.isPod{1, 2, a={4, 5, b=6}})
  assertEq(false, M.isPod{1, 2, a={4, 5, b=M.noop}})
end)

test('table', function()
  local t1, t2 = {1, 2}, {3, 4}
  assert(1 == indexOf(t2, 3)); assert(2 == indexOf(t2, 4))

  t1.a = t2
  local r = deepcopy(t1)
  assert(r[1] == 1)
  assert(r.a[1] == 3)
  t2[1] = 8
  assert(r.a[1] == 3)

  local t = {a=8, b=9}
  assert(8 == M.popk(t, 'a')) assert(9 == M.popk(t, 'b'))
  assert(0 == #t)

  assertEq(5,   getOrSet({a=5}, 'a', function() return 7 end))
  assertEq(7,   getOrSet({b=5}, 'a', function() return 7 end))
  assertEq(7,   get({a={b=7}}, {'a', 'b'}))
  assertEq(nil, get({}, {'a', 'b'}))

  local t = {}
  set(t, dp'a.b',   4);   assertEq(4, t.a.b)
  set(t, dp'a.a.a', 5);   assertEq(5, t.a.a.a)
  set(t, dp'a.a.a', nil); assertEq(nil, t.a.a.a)
  set(t, dp'a.b',   4);   assertEq(4, t.a.b)

  t = {}; for i, v in M.inext, {4, 5, 8}, 0 do t[i] = v end
  assertEq({4, 5, 8}, t)
  t = {}; for i, v in M.iprev, {4, 5, 8}, 4 do t[i] = v end
  assertEq({4, 5, 8}, t)
  t = {}; for i, v in M.ireverse{4, 5, 8} do t[i] = v end
  assertEq({4, 5, 8}, t)

  t = {}; for i, v in M.islice({5, 6, 7, 8, 9}, 2, 4) do push(t, v) end
  assertEq({6, 7, 8}, t)

  t = {}
  M.walk(
    {1, 2, a=3, inner={b=9, c='hi'}},
    function(k, v) t[k] = v end,
    function(k, v) t[k] = true end)
  assertEq({1, 2, a=3, b=9, c='hi', inner=true}, t)

  t = {} for _, v in M.ilast({1, 2, 3, 4, 5}, -3, -1) do push(t, v) end
  assertEq({3, 4, 5}, t)
  t = {} for _, v in M.ilast({1, 2, 3, 4, 5}, -3, -2) do push(t, v) end
  assertEq({3, 4}, t)
  t = {} for _, v in M.ilast({1, 2, 3, 4, 5}, -2, -2) do push(t, v) end
  assertEq({4}, t)
  t = {} for _, v in M.ilast({1, 2, 3, 4, 5}, -2) do push(t, v) end
  assertEq({4, 5}, t)

  t = M.Forget{a=4}
  assertEq(4, t.a)
  t.b = 7; t[1] = 4
  assertEq(nil, t.b); assertEq(nil, t[1])

  t = {4, 5, 6}
  assertEq({4, 5, 6, 7, 8}, M.add(t, 7, 8))

  t = {1, a=3, b={4, 5, b1=3}, c=3}
  assertEq({2, a=4, b={4, 7, 6, b1=3, b2=4}, c=3}, merge(t, {
    2, a=4, b={[2]=7, [3]=6, b2=4},
  }))

  assertEq(2, M.pairlen{1, 2})
  assertEq(3, M.pairlen{1, 2, z=4})

  assertEq({4, 2, 3}, M.icopy{4, 2, 3, a=4})

  assertEq({'a', 'b', 'c'}, M.orderedKeys{a=1, b=2, c=3})
  assertEq({'a', 'b', 'c', a=1, b=2, c=3}, M.pushSortedKeys{a=1, b=2, c=3})
end)

test('Slc', function()
  local Slc = M.Slc
  local a = Slc{si=2, ei=10}
  assertEq(9, #a); assertEq('Slc[2:10]', str(a))
  assertEq({Slc{si=2, ei=14}}, {a:merge(Slc{si=4, ei=14})})

  local expect = {Slc{si=2, ei=10}, Slc{si=12, ei=13}}
  assertEq(expect, {a:merge(Slc{si=12, ei=13})})
  assertEq(expect, {Slc{si=12, ei=13}:merge(a)})
end)

test('list', function()
  local t = {4, 5, 6}
  assertEq(4, M.geti(t, 1))
  assertEq(6, M.geti(t, -1))
  assertEq(5, M.geti(t, -2))

  assertEq({1, 2, 3}, extend({1}, {2, 3}))
  local t = {4, 5}; extend(t, {1, 2})
  assertEq({4, 5, 1, 2}, t)
  assertEq({}, clear{1, 2, 3})
  assertEq({1, 2}, replace({4, 5, 6}, {1, 2}))
  assertEq({1, 2}, replace({3}, {1, 2}))

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

  assertEq({}, M.inset({}, 1, {}))
  local t = M.inset({1}, 1, {}, 1)
  assertEq({}, t) -- remove
  assertEq({1, 2, 3}, M.inset({1, 3}, 2, {2}))
  assertEq({1, 2, 3}, M.inset({1, 4, 3}, 2, {2}, 1))
  assertEq({"ab", "d"}, M.inset({"ab", "c", "", "d"}, 2, {}, 2))
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
  assert(not G.seven) -- did not modify globals
end)

test('Set', function()
  local s = Set{'a', 'b', 'c'}
  assertEq(Set{'a', 'c', 'b'}, s)
  assertEq(Set{'a', 'b'}, s:union(Set{'a', 'b', 'z'}))
  assertEq(Set{'a'}, s:diff(Set{'b', 'c', 'z'}))
end)

test('LL', function(); local _
  local h = LL(2)
  assertEq({2}, h:tolist())

  -- '+' and '-'
  local res = h - LL(4)      assertEq({2, 4}, h:tolist())
  local t = h:tail();        assert(rawequal(t, res))
  _= h - (LL(5) + 6);        assertEq({2, 4, 5, 6}, h:tolist())

  -- pop
  h = LL:from{1, 2, 3, 4};   assertEq({1, 2, 3, 4}, h:tolist())
  local n2 = h.r
  local n3 = n2.r
    assert(not (rawequal(h, n2) or rawequal(h, n3)))
    assert(rawequal(n2,  h:get(1)))
    assert(rawequal(h,   n2.l))

  assertEq(nil, n2:rm())
    assertEq({1, 3, 4}, h:tolist())
    assert(rawequal(h.r, n3))
    assert(rawequal(h,   n3.l))
    assert(rawequal(n3, h:rm())) -- new head

  -- insert
  h = LL:from{1, 3, 4}
  h:insert(2);        assertEq({1, 2, 3, 4},    h:tolist())
    assert(rawequal(h, h.r.l))
  h:tail():insert(5); assertEq({1, 2, 3, 4, 5}, h:tolist())
    assertEq(4, h:tail().l.v)

  assertEq('LL{1 -> 3 -> 5}', str((LL:from{1, 3, 5})))
end)

test('binary-search', function()
  local bs = M.binarySearch
  local t = {1, 5, 8, 10, 12, 33}
  assertEq(0,   bs(t, -1))
  assertEq(1,   bs(t, 1))  assertEq(1,   bs(t, 4))
  assertEq(2,   bs(t, 5))  assertEq(2,   bs(t, 7))
  assertEq(5,   bs(t, 12)) assertEq(5,   bs(t, 32))
  assertEq(6,   bs(t, 33)) assertEq(6,   bs(t, 1024))
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


local function assertPath(fn, expect, p)
  assertEq(expect, fn(p))       -- pass in string
  assertEq(expect, fn(path(p))) -- pass in table
end
test('path', function()
  assertEq({'a', 'b', 'c'},  path('a/b/c'))
  assertEq({'/', 'b', 'c'},  path('/b/c'))
  assertEq({'a', 'b', 'c/'}, path('a/b/c/'))
  assertEq({'a', 'b', 'c'},  path{'a', 'b', 'c'})
  assertEq({'/', 'b', 'c'},  path{'/', 'b', 'c'})

  local pc = path.concat
  assertEq('foo/bar',   pc{'foo/', 'bar'})
  assertEq('/foo/bar',  pc{'/foo/', 'bar'})
  assertEq('/foo/bar/', pc{'/foo/', 'bar/'})
  assertEq('',          pc{''})
  assertEq('a/b',       pc{'a', '', 'b'})
  assertEq('a/b',       pc{'a/', '', 'b'})

  local pr = path.resolve
  assertEq({'/', '.a'},      pr('/.a'))
  assertEq({'/', '..a'},     pr('/..a'))
  assertEq({'/', 'a.'},      pr('/a.'))
  assertEq({'/', 'a..'},     pr('/a..'))
  assertEq({'a/'},           pr'a/b/..')
  assertEq({'b'},            pr'a/../b')
  assertEq({'b/'},           pr'a/../b/')
  assertEq({'/', 'a', 'b/'}, pr('..',       '/a/b/c/'))
  assertEq({'/', 'a', 'd/'}, pr('../../d/', '/a/b/c/'))
  assertEq({'/'},            pr('/a/..'))
  assertEq({},               pr('a/..'))
  assertErrorPat('before root', function() pr('/..')    end)
  assertErrorPat('before root', function() pr('/../..') end)
  assertErrorPat('before root', function() pr('/../../a') end)
  assertErrorPat('before root', function() pr('/a/../..') end)
  assertErrorPat('before root', function() pr('/a/../../') end)

  local pn = path.nice
  assertEq('./',        pn('a/..'))
  assertEq('/a/b/',     pn('..', '/a/b/c/'))
  assertEq('d/e',       pn('/a/b/c/d/e',  '/a/b/c'))
  assertEq('d/e/',      pn('/a/b/c/d/e/', '/a/b/c'))
  assertEq('a',         pn('./a'))

  local pe = path.ext
  assertPath(pe, 'foo', 'coo.foo')
  assertPath(pe, 'foo', 'a/b/c.foo')
  assertPath(pe, 'bar', 'a/b.c/d.foo.bar')

  local pf = path.first
  assertEq({'/',  'a/b/c/'}, {pf'/a/b/c/'})
  assertEq({'a',  'b/c/'},   {pf'a/b/c/'})
  assertEq({'/',  'a/b/'},   {pf'/a/b/'})
  assertEq({'/',  'a/b'},    {pf'/a/b'})
  assertEq({'/',  'b'},      {pf'/b'})
  assertEq({'b',  ''},       {pf'b'})
  assertEq({'/',  'b/'},     {pf'/b/'})
  assertEq({'/',  ''},       {pf'/'})

  local pl = path.last
  assertEq({'/a/b', 'c/'}, {pl'/a/b/c/'})
  assertEq({'a/b', 'c/'},  {pl'a/b/c/'})
  assertEq({'/a', 'b/'},   {pl'/a/b/'})
  assertEq({'/a', 'b'},    {pl'/a/b'})
  assertEq({'', '/b'},     {pl'/b'})
  assertEq({'', 'b'},      {pl'b'})
  assertEq({'', '/b/'},    {pl'/b/'})
  assertEq({'', '/'},      {pl'/'})

  assertEq(true, path.isDir('/'))
  assertEq('/',  path.toDir('/'))
  assertEq('a/', path.toDir('a'))
  assertEq('a',  path.toNonDir('a'))
  assertEq('a',  path.toNonDir('a/'))

  assertEq({'y', 'z/z', 'a/', 'a/b/'},
    M.sort({'a/', 'a/b/', 'z/z', 'y'}, path.cmpDirsLast))
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

  h = heap.Heap{1, 5, 9, 10, 3, 2, cmp=M.gt}
  assertPops({10, 9, 5, 3, 2, 1}, h)

  h = heap.Heap{{3}, {2}, {1}, cmp=function(a, b) return a[1] < b[1] end}
  assertPops({{1}, {2}, {3}}, h)
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

test('bimap', function()
  local bm = M.BiMap{'one', 'two'}
  assertEq(bm[1], 'one');   assertEq(bm.one, 1)
  assertEq(bm[2], 'two');   assertEq(bm.two, 2)
  bm[3] = 'three'
  assertEq(bm[3], 'three'); assertEq(bm.three, 3)
  assertEq('BiMap{"one", "two", "three", one=1, three=3, two=2}',
           str(bm))

  local bm = M.BiMap{a='A'}
  assertEq(bm.a, 'A'); assertEq(bm.A, 'a')
  bm.b = 'B'
  assertEq(bm.b, 'B'); assertEq(bm.B, 'b')
  assertEq('BiMap{A="a", B="b", a="A", b="B"}'
         , str(bm))
end)

test('deq', function()
  local d = M.Deq()
  d:pushRight(4); assertEq(1, #d)
  d:pushRight(5); assertEq(2, #d)
  d:pushLeft(3);  assertEq(3, #d)
  assertEq(3, d());          assertEq(2, #d)
  assertEq(5, d:popRight()); assertEq(1, #d)
  assertEq(4, d());          assertEq(0, #d)

  d = M.Deq()
  d:extendRight{1, 2}; d:extendLeft{4, 5}; d:extendRight{6, 7}
  setmetatable(d, nil)
  assertEq({[-1]=4, [0]=5, 1, 2, 6, 7, left=-1, right=4},
    setmetatable(d, nil))
  assertEq({4, 5, 1, 2, 6, 7}, setmetatable(d, M.Deq):drain())
  assertEq({left=1, right=0}, setmetatable(d, nil))
end)

local TB = [[
stack traceback:
        [C]: in function 'string.gsub'
        lib/ds/ds.lua:1064: in function 'ds.tracelist'
        lib/ds/ds.lua:1084: in function <lib/ds/ds.lua:1081>
]]
test('error', function()
  assertEq({
    "[C]: in function 'string.gsub'",
    "lib/ds/ds.lua:1064: in function 'ds.tracelist'",
    "lib/ds/ds.lua:1084: in function <lib/ds/ds.lua:1081>"
  }, M.tracelist(TB))

  local ok, err = M.try(c); assertEq(false, ok)
  M.clear(err.traceback, 4)
  local expect = M.Error{
    msg='a error',
    traceback={
      "lib/ds/test.lua:5: in upvalue 'a'",
      "lib/ds/test.lua:6: in upvalue 'b'",
      "lib/ds/test.lua:6: in function <lib/ds/test.lua:6>",
    },
  }
  assertEq(expect, err)

  local cor = coroutine.create(c)
  local ok, msg = coroutine.resume(cor)
  assert(not ok)
  assertEq(expect, M.Error.from(msg, cor))
end)

---------------------
-- ds/pod.lua
test('ds.pod', function()
  local pod = require'ds.pod'
  local test = mod'test'
  test.A = mty'A'{'a', 'b', b=3}
  test.A.__toPod = pod.__toPod; test.A.__fromPod = pod.__fromPod
  assertEq('test.A', PKG_NAMES[test.A])
  assertEq(test.A, PKG_LOOKUP['test.A'])
  local a = test.A{1, 2, a='hi'}
  assertEq({1, 2, a='hi', ['??']='test.A'}, pod.toPod(a))
  local result = pod.fromPod(pod.toPod(a))
  assertEq(a, result)
  assertEq(3, result.b)

  a = test.A{b=test.A{a='inner'}}
  assertEq(
    {b={a='inner', ['??']='test.A'}, ['??']='test.A'},
    pod.toPod(a))
  assertEq(a, pod.fromPod(pod.toPod(a)))
end)

---------------------
-- ds/Iter.lua
test('ds.Iter', function()
  local It = require'ds.Iter'
  local t = {4, 5, 'six', 7}

  local isNumber = function(v) return type(v) == 'number' end
  local numberVals = function(k, v) return isNumber(v)    end
  local plus2 = function(v) return v + 2 end
  local vToString = function(k, v) return k, tostring(v)  end

  assertEq(t, It:ofList(t):to())
  assertEq(t, It:of(t):to())
  assertEq(t, It:ofList(t):valsTo())
  assertEq({1, 2, 3, 4}, It:ofList(t):keysTo())

  assertEq({4, 5, [4]=7}, It:ofList(t):filter(numberVals):to())
  assertEq({1, 2, 4}, It:ofList(t):filter(numberVals):keysTo())
  assertEq({4, 5, 7}, It:ofList(t):filter(numberVals):valsTo())

  assertEq({4, 5, 7}, It:ofList(t):filterV(isNumber):valsTo())
  assertEq({6, 7, 9},
    It:ofList(t):filterV(isNumber):mapV(plus2):valsTo())

  local strs = {'4', '5', 'six', '7'}
  assertEq(strs, It:ofList(t):map(vToString):to())
  assertEq(strs, It:ofList(t):mapV(tostring):to())
  assertEq({1, 2, 3, 4}, It:ofList(t):mapV(tostring):keysTo())

  assertEq({['1'] = 4, ['2'] = 5, ['3'] = 'six', ['4'] = 7},
    It:of(t):mapK(tostring):to())

  local lk = {11, 22, 33, 44, 55, 'unused', 77, six=666}
  assertEq({11, 22, 33,  44}, It:ofList(t):lookupK(lk):keysTo())
  assertEq({44, 55, 666, 77}, It:of(t):lookupV(lk):to())


  local it = It:ofList(t):lookupK(lk)
  local res = {}; for k, v in it do push(res, k)end
  assertEq({11, 22, 33,  44}, res)

  -- local it = It:ofList(t):lookupK(lk)
  -- local res = {}; for k, v in it:iter() do push(res, k)end
  -- assertEq({11, 22, 33,  44}, res)

  -- local it = It:ofList(t):lookupV(lk)
  -- local res = {}; for k, v in it:iter() do res[k] = v end
  -- assertEq({44, 55, 666, 77}, res)

  -- use a big table
  local t = {}; for i=100,1,-1 do t[sfmt('%03i', i)] = i end
  assertEq(t['001'], 1); assertEq(t['100'], 100);
  local expect = {}; for i=1,100  do expect[i] = i end
  assertEq(expect, It:ofOrdMap(t):valsTo())
  assertEq(expect, It:ofOrdMap(t):index():to())

  assertEq({a=1, b=2, c=3}, It:of{'a', 'b', 'c'}:swap():to())

  local t = {10, 20, 30, 40, 50, 60}
  assertEq({40, 50, 60},             It:ofSlc(t, 4):valsTo())
  assertEq({[4]=40, [5]=50, [6]=60}, It:ofSlc(t, 4):to())

  assertEq({[2]=20, [4]=40}, It:of(t):keyIn{[2]=1,  [4]=1}:to())
  assertEq({[2]=20, [4]=40}, It:of(t):valIn{[20]=1, [40]=1}:to())

  assertEq(true,  It:of{true, true, true}:all())
  assertEq(false, It:of{true, false, true}:all())
  assertEq(true,  It:of{false, false, true, false}:any())
  assertEq(false, It:of{false, false, false, false}:any())
end)

---------------------
-- ds/utf8.lua

local function testU8(expect, chrs)
  local len = d8.decodelen(chrs[1]); assert(len, 'len is nil')
  assertEq(#chrs, len)
  c = d8.decode(chrs)
  assertEq(expect, utf8.char(c))
end

-- chrs were gotten from python:
--   print('{'+', '.join('0x%X' % c for c in '🙃'.encode('utf-8'))+'}')
-- Edge case characters are from:
--   https://design215.com/toolbox/ascii-utf8.php
test('u8edges', function()
  testU8('\0', {0})
  testU8(' ', {0x20})
  testU8('a', {string.byte('a')})
  testU8('~', {0x7E})

  testU8('¡', {0xC2, 0xA1})
  testU8('ƒ', {0xC6, 0x92})
  testU8('߿', {0xDF, 0xBF})

  testU8('ࠀ', {0xE0, 0xA0, 0x80})
  testU8('ἰ', {0xE1, 0xBC, 0xB0})
  testU8('‡', {0xE2, 0x80, 0xA1})
  testU8('➤', {0xE2, 0x9E, 0xA4})
  testU8('⮝', {0xE2, 0xAE, 0x9D})
  testU8('€', {0xE2, 0x82, 0xAC})
  testU8('�', {0xEF, 0xBF, 0xBD})

  testU8('𒀀',  {0xF0, 0x92, 0x80, 0x80})
  testU8('🙃', {0xF0, 0x9F, 0x99, 0x83})
  testU8('🧿', {0xF0, 0x9F, 0xA7, 0xBF})
end)

-----------------
-- Log
test('log', function()
  local L = require'ds.log'
  local fn, lvl = assert(LOGFN), assert(LOGLEVEL)
  local logs = {}
  LOGLEVEL = L.levelInt'INFO'
  LOGFN = function(lvl, loc, msg, data)
    push(logs, {lvl, msg, data}) -- skip loc
  end
  L.info'test info';              assertEq({4, 'test info'}, pop(logs))
  L.info('test %s', 'fmt');       assertEq({4, 'test fmt'}, pop(logs))
  L.info('test %s', 'data', {1});
    assertEq({4, 'test data', {1}}, pop(logs))

  LOGLEVEL = L.levelInt'WARN'
  L.info'test no log'; assertEq(0, #logs)
  L.warn'test warn';   assertEq({3, 'test warn'}, pop(logs))
  assertEq(0, #logs)
  LOGFN = fn

  LOGLEVEL = L.levelInt'INFO'
  -- test writing
  local cxt = ' [%d:]+ ds/test.lua:%d+: '
  local stderr = io.stderr
  local f = io.tmpfile(); io.stderr = f
  local assertLog = function(lvl, expect, fn, ...)
    f:seek'set'; fn(...); f:seek'set'
    local res = f:read'a'
    local m = lvl..cxt; assertMatch(m, res)
    assertEq(expect, res:sub(#res:match(m) + 1))
  end
  assertLog('I', 'test 42\n', L.info, 'test %s', 42)
  assertLog('I', 'test data {1}\n', L.info, 'test %s', 'data', {1})
  assertLog('I', 't {\n  1, 2, \n  key=42\n}\n',
            L.info, 't', {1, 2, key=42})
  io.stderr = stderr
  LOGLEVEL = lvl
end)

-----------------
-- Grid
test('Grid', function()
  local Grid = require'ds.Grid'
  local g = Grid{h=3, w=20}
    assertEq('\n\n', str(g))
  g:insert(2, 2, 'hello')
    assertEq('\n hello\n', str(g))
  g:insert(2, 4, ' is my friend') -- keeps 'he'
    assertEq('\n he is my friend\n', str(g))

  g:clear(); assertEq('\n\n', str(g))
  g:insert(1, 3, 'hi\n  bye\nfin')
    assertEq('  hi\n'
           ..'    bye\n'
           ..'  fin', str(g))

  g:insert(1, 10, 'there\nthen\n!')
    assertEq('  hi     there\n'
           ..'    bye  then\n'
           ..'  fin    !', str(g))

  g = Grid{h=3, w=20}
  g:insert(1, 1, {"13 5 7 9", " 2 4 6", ""})
    assertEq('13 5 7 9\n 2 4 6\n', str(g))

  g = Grid{h=3, w=20}
  g:insert(2, 3, "hi")
    assertEq('\n  hi\n', str(g))
  g:insert(1, 6, "ab\ncd\nef")
    assertEq(
      '     ab\n'
    ..'  hi cd\n'
    ..'     ef', str(g))
end)
