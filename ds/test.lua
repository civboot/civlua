METATY_CHECK = true

local mty = require'metaty'
local test, assertEq; mty.lrequire'civtest'

local min, max, bound, isWithin, sort2, decAbs
local indexOf, copy, deepcopy
local strInsert, strDivide, trimWs, splitWs
local pop, getOrSet, getPath, drain, reverse
local eval
local Set, LL, Duration, Epoch
local lines
mty.lrequire'ds'

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

  assertEq('hi there', trimWs('  hi there\n '))
  assertEq('hi there', trimWs('hi there'))
  assertEq({'1', 'ab', 'c'}, splitWs('  1 \n ab c'))
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
  assert(8 == pop(t, 'a')) assert(9 == pop(t, 'b'))
  assert(0 == #t)

  assertEq(5,   getOrSet({a=5}, 'a', function() return 7 end))
  assertEq(7,   getOrSet({b=5}, 'a', function() return 7 end))
  assertEq(7,   getPath({a={b=7}}, {'a', 'b'}))
  assertEq(nil, getPath({}, {'a', 'b'}))
  assertEq(nil, getPath({}, {'a', 'b'}))
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
  local l = lines.split'ab\nc\n\nd'
  assertEq({'ab'},      lsub(l, 1, 1))
  assertEq({'ab', 'c'}, lsub(l, 1, 2))
  assertEq({'c', ''},   lsub(l, 2, 3))
  assertEq('ab\n',      lsub(l, 1, 1, 1, 3))
  assertEq('b\nc',      lsub(l, 1, 2, 2, 1))

  l = lines.split"4     It's nice to have some real data"
  assertEq('It',     lsub(l, 1, 7, 1, 8))
  assertEq("'",      lsub(l, 1, 9, 1, 9))
  assertEq("s",      lsub(l, 1, 10, 1, 10))
  assertEq(" nice",  lsub(l, 1, 11, 1, 15))
end)
