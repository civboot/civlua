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
local fmt = require'fmt'
local ds = require'ds'; local M = ds
local lines = require'lines'
local testing = require'lines.testing'

local T = require'civtest'.Test()

local bound, isWithin, sort2, decAbs
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

T.loc = function()
  T.eq('lib/ds/test.lua:4', loc1)
  T.eq('ds/test.lua:4', loc2)

  T.eq(   'lib/ds/',          M.srcdir())
  T.matches('.*/lib/civtest/$', M.srcdir(1))
  local function fn()
     T.eq(   'lib/ds/',          M.srcdir())
     T.eq(   'lib/ds/',          M.srcdir(1))
     T.matches('.*/lib/civtest/$', M.srcdir(2))
  end; fn()
end

T.simplestr = function()
  T.eq('a', [[
a]])
  T.eq('this is\n  a simple str.', s[[
    this is
      a simple str.]])

  T.eq('easy',    s[[easy]])
  T.eq('easy  ',  s[[  easy  ]])
  T.eq('easy\nhi\nthere',  s[[easy
    hi
    there]])
  T.eq('easy',  s[[
  easy]])
  T.eq('newline\n\n', s[[
  newline

  ]])
end

T.bool_and_none = function()
  local none = assert(M.none)
  T.eq(false, M.bool())
  T.eq(false, M.bool(false))
  T.eq(false, M.bool(none))
  T.eq(true, M.bool(true))
  T.eq(true, M.bool(''))
  T.eq(true, M.bool(0))
  T.eq(true, M.bool({}))
  assert(none) -- truthy, use ds.bool for falsy
  assert(rawequal(none, none))
  assert(none == none)
  T.eq(none, none)
  assert(none ~= {})
  assert(not mty.eq(none, {}))
  T.eq('none', getmetatable(none))
  T.eq('none', mty.ty(none))
  T.eq('none', fmt(none))
  local err = 'invalid operation on sentinel'
  T.throws(err, function() none.foo = 3 end)
  T.throws(err, function() return #none end)
end

T.imm = function()
  T.eq({}, M.empty)
  T.eq(nil, next(M.empty))
  T.eq(0,  #M.empty)
  T.eq('table', getmetatable(M.empty))

  local t = M.Imm{1, 2, v=3}
  T.eq(1, t[1])
  T.eq(3, t.v)
  T.eq('table', getmetatable(t))
  assert('table', debug.getmetatable(t).__metatable)
  T.eq('table', mty.ty(t))
  T.throws('cannot modify Imm', function() t.b = 8 end)
  T.throws('cannot modify Imm', function() t.v = 8 end)
  T.eq('<!imm data!>', next(t))
  local j = {1, 2, v=3}
  local k = M.Imm{1, 2, v=4}
  assert(t == t); assert(t ~= j)
  T.eq(t, t)
  T.eq(t, j)

  assert(t ~= k); assert(not mty.eq(t, k))
  T.eq('{1, k=5}', fmt(M.Imm{1, k=5}))
  T.eq('table', mty.tyName(M.Imm{}))

  T.eq({1, 2, v=3}, j) -- table vs Imm
  assert(not mty.eq({1, 2}, j))

  T.eq({kind='Empty'}, M.Imm{kind='Empty'})
end

T.number = function()
  assert(0, decAbs(1)); assert(0, decAbs(-1))

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
end

T.str = function()
  T.eq('hi there', trim('  hi there\n '))
  T.eq('hi there', trim('hi there'))
  local multi = [[  one

three
four

]]
  T.eq('  one\n\nthree\nfour\n\n', multi)
  T.eq('one\n\nthree\nfour', trim(multi))

  T.eq('  a b c', M.trimEnd'  a b c')
  T.eq('  a b c', M.trimEnd'  a b c\n  ')

  T.eq(' a bc d e ', M.squash'  a   bc \td\te ')

  local u8 = "high🫸 five 🫷!"
  -- test utf8.offset itself
  local off = utf8.offset
  T.eq(4, off(u8, 4))
  T.eq(5, off(u8, 5)) -- start of 🫸
  T.eq(9, off(u8, 6));     T.eq(' five 🫷!', u8:sub(9))
  T.eq(9, off(u8, 1, 9))
  T.eq(19, off(u8, 8, 9)); T.eq('!', u8:sub(19))
  T.eq(2, off('a', 2))

  T.eq("high", M.usub(u8, 1, 4))
  T.eq("🫸 f", M.usub(u8, 5, 7))
  T.eq("🫷!",  M.usub(u8, -2))
  T.eq("e 🫷", M.usub(u8, -4, -2))
  T.eq('',     M.usub(u8, 100))
end

T.table = function()
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

  T.eq(5,   getOrSet({a=5}, 'a', function() return 7 end))
  T.eq(7,   getOrSet({b=5}, 'a', function() return 7 end))
  T.eq(7,   get({a={b=7}}, {'a', 'b'}))
  T.eq(nil, get({}, {'a', 'b'}))

  local t = {}
  set(t, dp'a.b',   4);   T.eq(4, t.a.b)
  set(t, dp'a.a.a', 5);   T.eq(5, t.a.a.a)
  set(t, dp'a.a.a', nil); T.eq(nil, t.a.a.a)
  set(t, dp'a.b',   4);   T.eq(4, t.a.b)

  t = {}; for i, v in M.inext, {4, 5, 8}, 0 do t[i] = v end
  T.eq({4, 5, 8}, t)
  t = {}; for i, v in M.iprev, {4, 5, 8}, 4 do t[i] = v end
  T.eq({4, 5, 8}, t)
  t = {}; for i, v in M.ireverse{4, 5, 8} do t[i] = v end
  T.eq({4, 5, 8}, t)

  t = {}; for i, v in M.islice({5, 6, 7, 8, 9}, 2, 4) do push(t, v) end
  T.eq({6, 7, 8}, t)

  t = {}
  M.walk(
    {1, 2, a=3, inner={b=9, c='hi'}},
    function(k, v) t[k] = v end,
    function(k, v) t[k] = true end)
  T.eq({1, 2, a=3, b=9, c='hi', inner=true}, t)

  t = {} for _, v in M.ilast({1, 2, 3, 4, 5}, -3, -1) do push(t, v) end
  T.eq({3, 4, 5}, t)
  t = {} for _, v in M.ilast({1, 2, 3, 4, 5}, -3, -2) do push(t, v) end
  T.eq({3, 4}, t)
  t = {} for _, v in M.ilast({1, 2, 3, 4, 5}, -2, -2) do push(t, v) end
  T.eq({4}, t)
  t = {} for _, v in M.ilast({1, 2, 3, 4, 5}, -2) do push(t, v) end
  T.eq({4, 5}, t)

  t = M.Forget{a=4}
  T.eq(4, t.a)
  t.b = 7; t[1] = 4
  T.eq(nil, t.b); T.eq(nil, t[1])

  t = {4, 5, 6}
  T.eq({4, 5, 6, 7, 8}, M.add(t, 7, 8))

  t = {1, a=3, b={4, 5, b1=3}, c=3}
  T.eq({2, a=4, b={4, 7, 6, b1=3, b2=4}, c=3}, merge(t, {
    2, a=4, b={[2]=7, [3]=6, b2=4},
  }))

  T.eq(2, M.pairlen{1, 2})
  T.eq(3, M.pairlen{1, 2, z=4})

  T.eq({4, 2, 3}, M.icopy{4, 2, 3, a=4})

  T.eq({'a', 'b', 'c'}, M.orderedKeys{a=1, b=2, c=3})
  T.eq({'a', 'b', 'c', a=1, b=2, c=3}, M.pushSortedKeys{a=1, b=2, c=3})

  T.eq({1}, M.sortUnique{1})
  T.eq({'a', 'b', 'c'}, M.sortUnique{'c', 'b', 'a'})
  T.eq({'a', 'b', 'c'}, M.sortUnique{'a', 'c', 'b', 'a'})
  T.eq({'.', 'h', 's'}, M.sortUnique{'h', '.', 's', 'h'})
end

T.Slc = function()
  local Slc = M.Slc
  local a = Slc{si=2, ei=10}
  T.eq(9, #a); T.eq('Slc[2:10]', fmt(a))
  T.eq({Slc{si=2, ei=14}}, {a:merge(Slc{si=4, ei=14})})

  local expect = {Slc{si=2, ei=10}, Slc{si=12, ei=13}}
  T.eq(expect, {a:merge(Slc{si=12, ei=13})})
  T.eq(expect, {Slc{si=12, ei=13}:merge(a)})
end

T.list = function()
  local t = {4, 5, 6}
  T.eq(4, M.geti(t, 1))
  T.eq(6, M.geti(t, -1))
  T.eq(5, M.geti(t, -2))

  T.eq({1, 2, 3}, extend({1}, {2, 3}))
  local t = {4, 5}; extend(t, {1, 2})
  T.eq({4, 5, 1, 2}, t)
  T.eq({}, clear{1, 2, 3})
  T.eq({1, 2}, replace({4, 5, 6}, {1, 2}))
  T.eq({1, 2}, replace({3}, {1, 2}))

  T.eq({1,2,5,7}, M.flatten({1,2},{5},{7}))

  local l = {'a', 'b', 'c', 1, 2, 3}
  T.eq({1, 2, 3}, drain(l, 3))
  T.eq({'a', 'b', 'c'}, l)
  T.eq({}, drain(l, 0))
  T.eq({'a', 'b', 'c'}, l)
  T.eq({'c'}, drain(l, 1))
  T.eq({'a', 'b'}, l)
  T.eq({'a', 'b'}, drain(l, 7))
  T.eq({}, l)

  T.eq({2, 1},    reverse({1, 2}))
  T.eq({3, 2, 1}, reverse({1, 2, 3}))

  T.eq({}, M.inset({}, 1, {}))
  local t = M.inset({1}, 1, {}, 1)
  T.eq({}, t) -- remove
  T.eq({1, 2, 3}, M.inset({1, 3}, 2, {2}))
  T.eq({1, 2, 3}, M.inset({1, 4, 3}, 2, {2}, 1))
  T.eq({"ab", "d"}, M.inset({"ab", "c", "", "d"}, 2, {}, 2))
end

T.eval = function()
  local env = {}
  local ok, err = eval('1+', env)
  assert(not ok); assert(err)
  local ok, three = eval('return 3', env)
  assert(ok); T.eq({}, env)
  T.eq(3, three)
  local ok, three = eval('seven = 7', env)
  assert(ok); T.eq({seven=7}, env)
  assert(not G.seven) -- did not modify globals
end

T.Set = function()
  local s = Set{'a', 'b', 'c'}
  T.eq(Set{'a', 'c', 'b'}, s)
  T.eq(Set{'a', 'b'}, s:union(Set{'a', 'b', 'z'}))
  T.eq(Set{'a'}, s:diff(Set{'b', 'c', 'z'}))
end

T.LL = function()
  local h, _ = LL(2)
  T.eq({2}, h:tolist())

  -- '+' and '-'
  local res = h - LL(4)      T.eq({2, 4}, h:tolist())
  local t = h:tail();        assert(rawequal(t, res))
  _= h - (LL(5) + 6);        T.eq({2, 4, 5, 6}, h:tolist())

  -- pop
  h = LL:from{1, 2, 3, 4};   T.eq({1, 2, 3, 4}, h:tolist())
  local n2 = h.r
  local n3 = n2.r
    assert(not (rawequal(h, n2) or rawequal(h, n3)))
    assert(rawequal(n2,  h:get(1)))
    assert(rawequal(h,   n2.l))

  T.eq(nil, n2:rm())
    T.eq({1, 3, 4}, h:tolist())
    assert(rawequal(h.r, n3))
    assert(rawequal(h,   n3.l))
    assert(rawequal(n3, h:rm())) -- new head

  -- insert
  h = LL:from{1, 3, 4}
  h:insert(2);        T.eq({1, 2, 3, 4},    h:tolist())
    assert(rawequal(h, h.r.l))
  h:tail():insert(5); T.eq({1, 2, 3, 4, 5}, h:tolist())
    T.eq(4, h:tail().l.v)

  T.eq('LL{1 -> 3 -> 5}', fmt((LL:from{1, 3, 5})))
end

T['binary-search'] = function()
  local bs = M.binarySearch
  local t = {1, 5, 8, 10, 12, 33}
  T.eq(0,   bs(t, -1))
  T.eq(1,   bs(t, 1))  T.eq(1,   bs(t, 4))
  T.eq(2,   bs(t, 5))  T.eq(2,   bs(t, 7))
  T.eq(5,   bs(t, 12)) T.eq(5,   bs(t, 32))
  T.eq(6,   bs(t, 33)) T.eq(6,   bs(t, 1024))
end

T.time = function()
  local N = Duration.NANO
  local d = Duration(3, 500)
  T.eq(Duration(2, 500),     Duration(3, 500) - Duration(1))
  T.eq(Duration(2, N - 900), Duration(3, 0)   - Duration(0, 900))
  T.eq(Duration(2, N - 800), Duration(3, 100) - Duration(0, 900))
  T.eq(Duration(2), Duration:fromMs(2000))
  assert(Duration(2) < Duration(3))
  assert(Duration(2) < Duration(2, 100))
  assert(not (Duration(2) < Duration(2)))
  T.eq(Duration(1.5), Duration(1, N * 0.5))
  T.eq('1.5s', tostring(Duration(1.5)))

  T.eq(Epoch(1) - Duration(1), Epoch(0))
  T.eq(Epoch(1) - Epoch(0), Duration(1))
  local e =    Epoch(1000001, 12342)
  T.eq(e - Epoch(1000000, 12342), Duration(1))
  T.eq('Epoch(1.5s)', tostring(Epoch(1.5)))
end


local function assertPath(fn, expect, p)
  T.eq(expect, fn(p))       -- pass in string
  T.eq(expect, fn(path(p))) -- pass in table
end
T.ds_path = function()
  T.eq({'a', 'b', 'c'},  path('a/b/c'))
  T.eq({'/', 'b', 'c'},  path('/b/c'))
  T.eq({'a', 'b', 'c/'}, path('a/b/c/'))
  T.eq({'a', 'b', 'c'},  path{'a', 'b', 'c'})
  T.eq({'/', 'b', 'c'},  path{'/', 'b', 'c'})

  local pc = path.concat
  T.eq('foo/bar',   pc{'foo/', 'bar'})
  T.eq('/foo/bar',  pc{'/foo/', 'bar'})
  T.eq('/foo/bar/', pc{'/foo/', 'bar/'})
  T.eq('',          pc{''})
  T.eq('a/b',       pc{'a', '', 'b'})
  T.eq('a/b',       pc{'a/', '', 'b'})

  local pr = path.resolve
  T.eq({'/', '.a'},      pr('/.a'))
  T.eq({'/', '..a'},     pr('/..a'))
  T.eq({'/', 'a.'},      pr('/a.'))
  T.eq({'/', 'a..'},     pr('/a..'))
  T.eq({'a/'},           pr'a/b/..')
  T.eq({'b'},            pr'a/../b')
  T.eq({'b/'},           pr'a/../b/')
  T.eq({'/', 'a', 'b/'}, pr('..',       '/a/b/c/'))
  T.eq({'/', 'a', 'd/'}, pr('../../d/', '/a/b/c/'))
  T.eq({'/'},            pr('/a/..'))
  T.eq({},               pr('a/..'))
  T.throws('before root', function() pr('/..')    end)
  T.throws('before root', function() pr('/../..') end)
  T.throws('before root', function() pr('/../../a') end)
  T.throws('before root', function() pr('/a/../..') end)
  T.throws('before root', function() pr('/a/../../') end)

  local pn = path.nice
  T.eq('./',        pn('a/..'))
  T.eq('/a/b/',     pn('..', '/a/b/c/'))
  T.eq('d/e',       pn('/a/b/c/d/e',  '/a/b/c'))
  T.eq('d/e/',      pn('/a/b/c/d/e/', '/a/b/c'))
  T.eq('a',         pn('./a'))

  local pe = path.ext
  assertPath(pe, 'foo', 'coo.foo')
  assertPath(pe, 'foo', 'a/b/c.foo')
  assertPath(pe, 'bar', 'a/b.c/d.foo.bar')

  local pf = path.first
  T.eq({'/',  'a/b/c/'}, {pf'/a/b/c/'})
  T.eq({'a',  'b/c/'},   {pf'a/b/c/'})
  T.eq({'/',  'a/b/'},   {pf'/a/b/'})
  T.eq({'/',  'a/b'},    {pf'/a/b'})
  T.eq({'/',  'b'},      {pf'/b'})
  T.eq({'b',  ''},       {pf'b'})
  T.eq({'/',  'b/'},     {pf'/b/'})
  T.eq({'/',  ''},       {pf'/'})

  local pl = path.last
  T.eq({'/a/b/', 'c/'}, {pl'/a/b/c/'})
  T.eq({'a/b/', 'c/'},  {pl'a/b/c/'})
  T.eq({'/a/', 'b/'},   {pl'/a/b/'})
  T.eq({'/a/', 'b'},    {pl'/a/b'})
  T.eq({'', '/b'},      {pl'/b'})
  T.eq({'', 'b'},       {pl'b'})
  T.eq({'', '/b/'},     {pl'/b/'})
  T.eq({'', '/'},       {pl'/'})

  T.eq(true, path.isDir('/'))
  T.eq('/',  path.toDir('/'))
  T.eq('a/', path.toDir('a'))
  T.eq('a',  path.toNonDir('a'))
  T.eq('a',  path.toNonDir('a/'))

  T.eq({'y', 'z/z', 'a/', 'a/b/'},
    M.sort({'a/', 'a/b/', 'z/z', 'y'}, path.cmpDirsLast))
end

local heap = require'ds.heap'

local function pushh(h, t)
  for i, v in ipairs(t) do h:add(v) end
end

local function assertPops(expect, h)
  local t = {}; while #h > 0 do
    push(t, h:pop())
  end
  T.eq(expect, t)
end
T.heap = function()
  local h = heap.Heap{1, 5, 9, 10, 3, 2}
  assertPops({1, 2, 3, 5, 9, 10}, h)
  T.eq(0, #h)
  pushh(h, {8, 111, -1, 333, 42})
  T.eq(heap.Heap{-1, 42, 8, 333, 111}, h)
  assertPops({-1, 8, 42, 111, 333}, h)

  h = heap.Heap{1, 5, 9, 10, 3, 2, cmp=M.gt}
  assertPops({10, 9, 5, 3, 2, 1}, h)

  h = heap.Heap{{3}, {2}, {1}, cmp=function(a, b) return a[1] < b[1] end}
  assertPops({{1}, {2}, {3}}, h)
end

T.dag = function()
  local childrenMap = {
    a = {'b', 'c'},
    b = {'c', 'd'},
    c = {'d'}, d = {},
  }
  local parentsMap = M.dag.reverseMap(childrenMap)
  for _, v in pairs(parentsMap) do table.sort(v) end
  T.eq({
    d = {'b', 'c'}, c = {'a', 'b'},
    b = {'a'},      a = {},
  }, parentsMap)

  local result = M.dag.reverseMap(parentsMap)
  for _, v in pairs(result) do table.sort(v) end
  T.eq(childrenMap, result)

  T.eq({'d', 'c', 'b', 'a'}, M.dag.sort(childrenMap))
end

T.bimap = function()
  local bm = M.BiMap{'one', 'two'}
  T.eq(bm[1], 'one');   T.eq(bm.one, 1)
  T.eq(bm[2], 'two');   T.eq(bm.two, 2)
  bm[3] = 'three'
  T.eq(bm[3], 'three'); T.eq(bm.three, 3)
  T.eq('BiMap{"one", "two", "three", one=1, three=3, two=2}',
           fmt(bm))

  local bm = M.BiMap{a='A'}
  T.eq(bm.a, 'A'); T.eq(bm.A, 'a')
  bm.b = 'B'
  T.eq(bm.b, 'B'); T.eq(bm.B, 'b')
  T.eq('BiMap{A="a", B="b", a="A", b="B"}'
         , fmt(bm))
end

T.deq = function()
  local d = M.Deq()
  d:pushRight(4); T.eq(1, #d)
  d:pushRight(5); T.eq(2, #d)
  d:pushLeft(3);  T.eq(3, #d)
  T.eq(3, d());          T.eq(2, #d)
  T.eq(5, d:popRight()); T.eq(1, #d)
  T.eq(4, d());          T.eq(0, #d)

  d = M.Deq()
  d:extendRight{1, 2}; d:extendLeft{4, 5}; d:extendRight{6, 7}
  setmetatable(d, nil)
  T.eq({[-1]=4, [0]=5, 1, 2, 6, 7, left=-1, right=4},
    setmetatable(d, nil))
  T.eq({4, 5, 1, 2, 6, 7}, setmetatable(d, M.Deq):drain())
  T.eq({left=1, right=0}, setmetatable(d, nil))
end

local TB = [[
stack traceback:
        [C]: in function 'string.gsub'
        lib/ds/ds.lua:1064: in function 'ds.tracelist'
        lib/ds/ds.lua:1084: in function <lib/ds/ds.lua:1081>
]]
T.error = function()
  T.throws('expect failure', function()
    M.check(3, nil, nil, 'expect failure', 'other')
  end)
  T.eq({'a', nil, 'c'}, {M.check(2, 'a', nil, 'c')})

  T.eq({
    "[C]: in function 'string.gsub'",
    "lib/ds/ds.lua:1064: in function 'ds.tracelist'",
    "lib/ds/ds.lua:1084: in function <lib/ds/ds.lua:1081>"
  }, M.tracelist(TB))

  local ok, err = M.try(c); T.eq(false, ok)
  M.clear(err.traceback, 4)
  local expect = M.Error{
    msg='a error',
    traceback={
      "lib/ds/test.lua:5: in upvalue 'a'",
      "lib/ds/test.lua:6: in upvalue 'b'",
      "lib/ds/test.lua:6: in function <lib/ds/test.lua:6>",
    },
  }
  T.eq(expect, err)

  local cor = coroutine.create(c)
  local ok, msg = coroutine.resume(cor)
  assert(not ok)
  T.eq(expect, M.Error.from(msg, cor))
end

---------------------
-- ds/Iter.lua
T['ds.Iter'] = function()
  local It = require'ds.Iter'
  local t = {4, 5, 'six', 7}

  local isNumber = function(v) return type(v) == 'number' end
  local numberVals = function(k, v) return isNumber(v)    end
  local plus2 = function(v) return v + 2 end
  local vToString = function(k, v) return k, tostring(v)  end

  T.eq(t, It:ofList(t):to())
  T.eq(t, It:of(t):to())
  T.eq(t, It:ofList(t):valsTo())
  T.eq({1, 2, 3, 4}, It:ofList(t):keysTo())

  T.eq({4, 5, [4]=7}, It:ofList(t):filter(numberVals):to())
  T.eq({1, 2, 4}, It:ofList(t):filter(numberVals):keysTo())
  T.eq({4, 5, 7}, It:ofList(t):filter(numberVals):valsTo())

  T.eq({4, 5, 7}, It:ofList(t):filterV(isNumber):valsTo())
  T.eq({6, 7, 9},
    It:ofList(t):filterV(isNumber):mapV(plus2):valsTo())

  local strs = {'4', '5', 'six', '7'}
  T.eq(strs, It:ofList(t):map(vToString):to())
  T.eq(strs, It:ofList(t):mapV(tostring):to())
  T.eq({1, 2, 3, 4}, It:ofList(t):mapV(tostring):keysTo())

  T.eq({['1'] = 4, ['2'] = 5, ['3'] = 'six', ['4'] = 7},
    It:of(t):mapK(tostring):to())

  local lk = {11, 22, 33, 44, 55, 'unused', 77, six=666}
  T.eq({11, 22, 33,  44}, It:ofList(t):lookupK(lk):keysTo())
  T.eq({44, 55, 666, 77}, It:of(t):lookupV(lk):to())


  local it = It:ofList(t):lookupK(lk)
  local res = {}; for k, v in it do push(res, k)end
  T.eq({11, 22, 33,  44}, res)

  -- local it = It:ofList(t):lookupK(lk)
  -- local res = {}; for k, v in it:iter() do push(res, k)end
  -- T.eq({11, 22, 33,  44}, res)

  -- local it = It:ofList(t):lookupV(lk)
  -- local res = {}; for k, v in it:iter() do res[k] = v end
  -- T.eq({44, 55, 666, 77}, res)

  -- use a big table
  local t = {}; for i=100,1,-1 do t[sfmt('%03i', i)] = i end
  T.eq(t['001'], 1); T.eq(t['100'], 100);
  local expect = {}; for i=1,100  do expect[i] = i end
  T.eq(expect, It:ofOrdMap(t):valsTo())
  T.eq(expect, It:ofOrdMap(t):index():to())

  T.eq({a=1, b=2, c=3}, It:of{'a', 'b', 'c'}:swap():to())

  local t = {10, 20, 30, 40, 50, 60}
  T.eq({40, 50, 60},             It:ofSlc(t, 4):valsTo())
  T.eq({[4]=40, [5]=50, [6]=60}, It:ofSlc(t, 4):to())

  T.eq({[2]=20, [4]=40}, It:of(t):keyIn{[2]=1,  [4]=1}:to())
  T.eq({[2]=20, [4]=40}, It:of(t):valIn{[20]=1, [40]=1}:to())

  T.eq(true,  It:of{true, true, true}:all())
  T.eq(false, It:of{true, false, true}:all())
  T.eq(true,  It:of{false, false, true, false}:any())
  T.eq(false, It:of{false, false, false, false}:any())

  It{ipairs{11, 12, 13}}:assertEq(It{ipairs{11, 12, 13}})

  local i = 0
  local it = It{function()
    if i >= 3 then return end
    i = i + 1; return i, 10 + i
  end}
  It{ipairs{11, 12, 13}}:assertEq(it)

  it = It:ofUnpacked{{11, 'first'}, {22, 'second'}}
  T.eq({11, 'first'},  {it()})
  T.eq({22, 'second'}, {it()})
  T.eq(nil, it())
end

---------------------
-- ds/utf8.lua

local function testU8(expect, chrs)
  local len = d8.decodelen(chrs[1]); assert(len, 'len is nil')
  T.eq(#chrs, len)
  c = d8.decode(chrs)
  T.eq(expect, utf8.char(c))
end

-- chrs were gotten from python:
--   print('{'+', '.join('0x%X' % c for c in '🙃'.encode('utf-8'))+'}')
-- Edge case characters are from:
--   https://design215.com/toolbox/ascii-utf8.php
T.u8edges = function()
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
end

-----------------
-- Log
T.log = function()
  local L = require'ds.log'
  local fn, lvl = assert(LOGFN), assert(LOGLEVEL)
  local logs = {}
  LOGLEVEL = L.levelInt'INFO'
  LOGFN = function(lvl, loc, ...)
    push(logs, {lvl, ...}) -- skip loc
  end
  L.info'test info';              T.eq({4, 'test info'}, pop(logs))
  L.info('test %s', 'fmt')
    T.eq({4, 'test %s', 'fmt'}, pop(logs))

  L.info('test %s', 'data', {1})
    T.eq({4, 'test %s', 'data', {1}}, pop(logs))

  LOGLEVEL = L.levelInt'WARN'
  L.info'test no log'; T.eq(0, #logs)
  L.warn'test warn';   T.eq({3, 'test warn'}, pop(logs))
  T.eq(0, #logs)
  LOGFN = fn

  LOGLEVEL = L.levelInt'INFO'
  -- test writing
  local cxt = ' [%d:]+ ds/test.lua:%d+: '
  local iofmt = io.fmt
  local f = io.tmpfile()
  io.fmt = fmt.Fmt:pretty{to=f}
  local assertLog = function(lvl, expect, fn, ...)
    f:seek'set'; fn(...); f:seek'set'
    local res = f:read'a'
    local m = lvl..cxt; T.matches(m, res)
    T.eq(expect, res:sub(#res:match(m) + 1))
  end
  assertLog('I', 'test 42\n', L.info, 'test %s', 42)
  assertLog('I', 'test data {1}\n', L.info, 'test %s', 'data', {1})
  assertLog('I', 't {\n    1, 2, \n    key=42\n  }\n',
            L.info, 't', {1, 2, key=42})
  io.fmt = iofmt
  LOGLEVEL = lvl
end

-----------------
-- Grid
T.Grid = function()
  local Grid = require'ds.Grid'
  local g = Grid{h=3, w=20}
    T.eq('\n\n', fmt(g))
  g:insert(2, 2, 'hello')
    T.eq('\n hello\n', fmt(g))
  g:insert(2, 4, ' is my friend') -- keeps 'he'
    T.eq('\n he is my friend\n', fmt(g))

  g:clear(); T.eq('\n\n', fmt(g))
  g:insert(1, 3, 'hi\n  bye\nfin')
    T.eq('  hi\n'
           ..'    bye\n'
           ..'  fin', fmt(g))

  g:insert(1, 10, 'there\nthen\n!')
    T.eq('  hi     there\n'
           ..'    bye  then\n'
           ..'  fin    !', fmt(g))

  g = Grid{h=3, w=20}
  g:insert(1, 1, {"13 5 7 9", " 2 4 6", ""})
    T.eq('13 5 7 9\n 2 4 6\n', fmt(g))

  g = Grid{h=3, w=20}
  g:insert(2, 3, "hi")
    T.eq('\n  hi\n', fmt(g))
  g:insert(1, 6, "ab\ncd\nef")
    T.eq(
      '     ab\n'
    ..'  hi cd\n'
    ..'     ef', fmt(g))
end

-----------------
-- kev
T.kev = function()
  local kev = require'ds.kev'
  local t = {a='value a', b='value b', e=''}
  local r = {'a=value a', 'b=value b', 'e='}
  T.eq(r, kev.to(t))
  T.eq(t, kev.from(r))
  push(r, 'this has no equal sign and is ignored')
  T.eq(t, kev.from(r))
end
