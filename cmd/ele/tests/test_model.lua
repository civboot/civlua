METATY_CHECK = true

local pkg = require'pkg'
local mty = pkg'metaty'
local tostring = mty.tostring
local test, assertEq; pkg.auto'civtest'

local ds = pkg'ds'
local buffer = pkg'rebuf.buffer'
local keys = pkg'ele.keys'
local model = pkg'ele.model'
local term = pkg'civix.term'
local T = pkg'ele.types'
local window = pkg'ele.window'
local data = pkg'ele.data'
local action = pkg'ele.action'
local A = action.Actions
local FakeTerm = pkg'ele.FakeTerm'

local add = table.insert

test('keypress', function()
  assertEq({'a', 'b'},  keys.parseKeys('a b'))
  assertEq({'a', '^B'}, keys.parseKeys('a ^b'))
  assertEq({'a', '^B'}, keys.parseKeys('a ^b'))
  assertEq({'return', '^B'}, keys.parseKeys('return ^b'))
end)

test('ctrl', function()
  assertEq('P', term.ctrlChar(16))
end)

local function mockInputs(inputs)
  return keys.parseKeys(inputs)
end

test('edit (only)', function()
  local t = FakeTerm(1, 4); assert(t)
  local e = T.Edit.new(nil, buffer.Buffer.new("1234567\n123\n12345\n"))
  e.tl, e.tc, e.th, e.tw = 1, 1, 1, 4
  e:draw(t, true); assertEq({'1234'}, e.canvas)
  e.th, e.tw = 2, 4; t:init(2, 4)
  e:draw(t, true)
  assertEq({'1234', '123'}, e.canvas)
  e.l, e.vl = 2, 2; e:draw(t, true)
  assertEq({'123', '1234'}, e.canvas)
  assertEq("123\n1234", tostring(t))
end)

local function mockedModel(h, w, s, inputs)
  T.ViewId = 0
  local mdl = T.Model.new(
    FakeTerm(h, w),
    ds.iterV(mockInputs(inputs or '')))
  local e = mdl:newEdit(nil, s)
  e.container, mdl.view, mdl.edit = mdl, e, e
  mdl:init()
  return mdl
end

test('bindings', function()
  local m = mockedModel(5, 5)
  assertEq(m:getBinding('^U'), {'up', times=15})
  local spc = m:getBinding('space')
  local win = assert(spc.w)
  assertEq(win.V, A.splitVertical)
end)


local function testModel(h, w)
  local mdl, status, eTest = model.testModel(
    FakeTerm(h, w), ds.iterV(mockInputs('')))
  mdl:init()
  return mdl, status, eTest
end

test('insert', function()
  local m = mockedModel(
    1, 4, -- h, w
    '1234567\n123\n12345\n',
    '1 2 i 8 9')
  assertEq('1', m.inputCo())
  assertEq('2', m.inputCo())
  local e = m.edit;
  assertEq(1, e.l); assertEq(1, e.c)
  m:step(); assertEq({'1234'}, e.canvas)
            assertEq(1, e.l); assertEq(1, e.c)
  m:step(); assertEq({'8123'}, e.canvas)
            assertEq(1, e.l); assertEq(2, e.c)
  m:step(); assertEq({'8912'}, e.canvas)
            assertEq(1, e.l); assertEq(3, e.c)
end)

test('back', function()
  local m = mockedModel(
    1, 7, -- h, w
    '1234567',
    'i back back x')
  local e = m.edit;
  e.l, e.c = 1, 4 -- '4'
  m:step(); assertEq({'1234567'}, e.canvas) -- i
            assertEq(1, e.l); assertEq(4, e.c)
  m:step(); assertEq({'124567'}, e.canvas) -- back
            assertEq(1, e.l); assertEq(3, e.c)
  m:step(); assertEq({'14567'}, e.canvas)  -- back
            assertEq(1, e.l); assertEq(2, e.c)
  m:step(); assertEq({'1x4567'}, e.canvas)
            assertEq(1, e.l); assertEq(3, e.c)
end)

local function steps(m, num) for _=1, num do m:step() end end
local function stepKeys(m, keys)
  local inp = mockInputs(keys)
  m.inputCo = ds.iterV(inp)
  for _ in ipairs(inp) do m:step() end
end

test('move', function()
  local m = mockedModel(
    1, 7, -- h, w
    '1234567\n123\n12345',
    'k l h j j') -- up right left down down
  local e = m.edit; e.l, e.c = 2, 3            -- '3' (l 2)
  m:step(); assertEq(1, e.l); assertEq(3, e.c) -- k '3' (l 1)
  m:step(); assertEq(1, e.l); assertEq(4, e.c) -- l '4' (l 1)
  m:step(); assertEq(1, e.l); assertEq(3, e.c) -- h '3' (l 1)
  m:step(); assertEq(2, e.l); assertEq(3, e.c) -- j '3' (l 2)
  m:step(); assertEq(3, e.l); assertEq(3, e.c) -- j '3' (l 3)

  -- now test boundaries
  m.inputCo = ds.iterV(mockInputs('j $ k l')) -- down RIGHT up right
  m:step(); assertEq(3, e.l); assertEq(3, e.c) -- '\n' (l 3 EOF)
  m:step(); assertEq(3, e.l); assertEq(6, e.c) -- '\n' (l 3 EOF)
  m:step(); assertEq(2, e.l); assertEq(6, e.c) -- '\n' (l 2)
  m:step(); assertEq(2, e.l); assertEq(4, e.c) -- '\n' l2  (overflow set)

  -- now test insert on overflow
  -- up 3*right down insert-x-
  m.inputCo = ds.iterV(mockInputs('k l l l j i x'))  -- k l l l
  steps(m, 4); assertEq(1, e.l); assertEq(7, e.c); -- '7' (l 1)
               assertEq(1, e.vl)
  m:step();    assertEq(2, e.l); assertEq(7, e.c); -- j (l2 overflow)
               assertEq(2, e.vl)
  m:step();    assertEq(2, e.l); assertEq(7, e.c); -- i
  m:step();    assertEq({2, 5}, {e.l, e.c}) -- x
               assertEq({'123x'}, e.canvas)

  -- now test multi-movement
  stepKeys(m, '^J ^U'); assertEq({1, 5}, {e.l, e.c})
end)

local function splitSetup(m, kind)
  local eR = m.edit
  local eL = window.splitEdit(m.edit, kind)
  local w = eL.container
  assert(rawequal(w, m.view))
  assert(rawequal(w, eR.container))
  assert(rawequal(eR.buf, eL.buf))
  assertEq(eL, w[1]); assertEq(eR, w[2]);
  m:draw()
  return w, eL, eR
end

test('splitH', function()
  local m = mockedModel(
    5, 7, -- h, w
    '1234567\n123')
  local w, eL, eR = splitSetup(m, 'h')
  assertEq(7, w.tw)
  assertEq(7, eR.tw); assertEq(7, eL.tw)
  assertEq(2, eR.th); assertEq(2, eL.th)
  assertEq([[
1234567
123
-------
1234567
123]], tostring(m.term))
end)

test('splitV', function()
  local m = mockedModel(
    2, 20, -- h, w
    '1234567\n123')
  local w, eL, eR = splitSetup(m, 'v')
  assertEq(20, w.tw)
  assertEq(10, eR.tw)
  assertEq(9,  eL.tw)
  assertEq([[
1234567  |1234567
123      |123]], tostring(m.term))
end)

test('splitEdit', function()
  local m = mockedModel(
    5, 7, -- h, w
    '1234567\n123')
  local w, eT, eB = splitSetup(m, 'h')
  stepKeys(m, 'i a b c')
  assertEq([[
abc1234
123
-------
abc1234
123]], tostring(m.term))
  -- go down twice (to EOF) then insert stuff
  stepKeys(m, '^J j j i 4 return b o t t o m')
  assertEq([[
abc1234
1234
-------
1234
bottom]], tostring(m.term))
    assertEq(3, eB.l); assertEq(7, eB.c)
end)


test('withStatus', function()
  local h, w = 9, 16
  local m, status, eTest = testModel(h, w)
  local t = m.term
  m:draw()
  assertEq(eTest, m.edit)
  assertEq(1, ds.indexOf(m.view, eTest))
  assertEq(2, ds.indexOf(m.view, status))
  assertEq(1, status.fh); assertEq(1, status:forceHeight())
  assertEq(1, m.view:forceDim('forceHeight', false))
  assertEq(7, m.view:period(9, 'forceHeight', 1))

  assertEq([[
*123456789*12345
1 This is to man
2               
3               
4     It's nice 
5               
6               
----------------
]], tostring(t))

  stepKeys(m, 'i h i space ^J ~') -- type a bit, trigger status
  assertEq([[
hi *123456789*12
1 This is to man
2               
3               
4     It's nice 
5               
6               
----------------
[unset] chord: ~]], tostring(t))
end)

test('moveWord', function()
  local m = mockedModel(
    1, 7, -- h, w
    ' bc+12 -de \n  z(45+ 7)')
  local e = m.edit; e.l, e.c = 1, 1
  stepKeys(m, 'w'); assertEq(1, e.l); assertEq(e.c, 2) -- 'bc'
  stepKeys(m, 'w'); assertEq(1, e.l); assertEq(e.c, 4) -- '+'
  stepKeys(m, 'w'); assertEq(1, e.l); assertEq(e.c, 5) -- '12'
  stepKeys(m, 'w'); assertEq(1, e.l); assertEq(e.c, 8) -- '-'
  stepKeys(m, 'w'); assertEq(1, e.l); assertEq(e.c, 9) -- 'de'
  stepKeys(m, 'w'); assertEq(2, e.l); assertEq(e.c, 3) -- 'z' (next line)

  stepKeys(m, 'b'); assertEq(1, e.l); assertEq(e.c, 9) -- 'de'
  stepKeys(m, 'b'); assertEq(1, e.l); assertEq(e.c, 8) -- '-'
  stepKeys(m, 'b'); assertEq(1, e.l); assertEq(e.c, 5) -- '12'
  stepKeys(m, 'b'); assertEq(1, e.l); assertEq(e.c, 4) -- '+'
  stepKeys(m, 'b'); assertEq(1, e.l); assertEq(e.c, 2) -- 'bc'
  stepKeys(m, 'b'); assertEq(1, e.l); assertEq(e.c, 1) -- SOL
  stepKeys(m, 'j b'); assertEq(1, e.l); assertEq(e.c, 9)  -- 'de'
end)

------------
-- Test D C modline
local MODLINE_0 = '12345\n8909876'
test('modLine', function()
  local m = mockedModel(2, 8, MODLINE_0)
  local e, t = m.edit, m.term
  e.l, e.c = 1, 1
  stepKeys(m, 'A 6 7 ^J'); assertEq(1, e.l); assertEq(8, e.c)
  assertEq('1234567\n8909876', tostring(t))
  stepKeys(m, 'h h D'); assertEq(1, e.l); assertEq(6, e.c)
    assertEq(MODLINE_0, tostring(t))
  stepKeys(m, 'h h C'); assertEq(1, e.l); assertEq(4, e.c)
    assertEq('insert', m.mode)
  stepKeys(m, 'a b c ^J'); assertEq(1, e.l); assertEq(7, e.c)
    assertEq('123abc\n8909876', tostring(t))
  stepKeys(m, '0'); assertEq(1, e.l); assertEq(1, e.c)
  stepKeys(m, '$'); assertEq(1, e.l); assertEq(7, e.c)
  stepKeys(m, 'o h i ^J'); assertEq(2, e.l); assertEq(3, e.c)
    assertEq('123abc\nhi', tostring(t))
  stepKeys(m, 'k 0 x x'); assertEq(1, e.l); assertEq(1, e.c)
    assertEq('3abc\nhi', tostring(t))
end)

------------
-- Test d delete
local DEL = '12 34+56\n78+9'
test('deleteChain', function()
  local m = mockedModel(1, 8, '12 34 567')
  local e, t = m.edit, m.term; e.l, e.c = 1, 1
  stepKeys(m, 'd w'); assertEq(1, e.l); assertEq(1, e.c)
    assertEq('34 567', tostring(t))
  stepKeys(m, '2 d w'); assertEq(1, e.l); assertEq(1, e.c)
     assertEq('', tostring(t))
  e.buf.gap:insert(DEL, 1, 1)
  t:init(2, 8); m:draw(); assertEq(DEL, tostring(t))
  stepKeys(m, 'l j d d');
     assertEq(1, e.l); assertEq(2, e.c)
     assertEq('12 34+56\n', tostring(t))
  stepKeys(m, 'f 4');
    assertEq(1, e.l); assertEq(5, e.c)
  stepKeys(m, 'd f 5');
     assertEq(1, e.l); assertEq(5, e.c)
     assertEq('12 356\n', tostring(t))

  stepKeys(m, 'd F 2');
    assertEq(1, e.l); assertEq(2, e.c)
    assertEq('156\n', tostring(t))
  stepKeys(m, 'g g d G')
    assertEq(1, e.l); assertEq(1, e.c)
    assertEq('\n', tostring(t))
end)

------------
-- Test c delete
test('change', function()
  local m = mockedModel(1, 12, '12 34 567')
  local e, t = m.edit, m.term; e.l, e.c = 1, 4
  stepKeys(m, 'c w'); assertEq(1, e.l); assertEq(4, e.c)
    assertEq('12 567', tostring(t))
    assertEq('insert', m.mode)
  stepKeys(m, 'a b c space ^J'); assertEq(1, e.l); assertEq(8, e.c)
    assertEq('12 abc 567', tostring(t))
  stepKeys(m, 'r Z'); assertEq(1, e.l); assertEq(8, e.c)
    assertEq('12 abc Z67', tostring(t))
end)

------------
-- Test /search
local SEARCH_0 = '12345\n12345678\nabcdefg'
test('modLine', function()
  local m = mockedModel(3, 9, SEARCH_0)
  local e, t, s, sch = m.edit, m.term, m.statusEdit, m.searchEdit
  e.l, e.c = 1, 1
  stepKeys(m, '/ 3 4'); assertEq(1, e.l); assertEq(1, e.c)
  assertEq([[
12345
---------
34]], tostring(t))
  stepKeys(m, 'return'); assertEq(1, e.l); assertEq(3, e.c)
    assertEq(SEARCH_0, tostring(t))
  stepKeys(m, '/ 2 3 4'); assertEq(1, e.l); assertEq(3, e.c)
  assertEq([[
12345
---------
234]], tostring(t))
  stepKeys(m, 'return'); assertEq(2, e.l); assertEq(2, e.c)
    assertEq(SEARCH_0, tostring(t))

  m:showStatus(); m:draw()
  assertEq([[
12345678
---------
]], tostring(t))

  stepKeys(m, '/ 1 2 3')
  assertEq(m.view[1], e)
  assertEq(m.view[2][1], sch)
  assertEq(m.view[2][2], s)
  assertEq(1, m.view[2]:forceHeight())
  assertEq({1, 4}, {s.th, s.tw})
  assertEq({2, 2, 1, 9}, {e.l, e.c, e.th, e.tw})
  assertEq([[
12345678
---------
123 |]], tostring(t))
  stepKeys(m, 'return')
assertEq([[
12345678
---------
[find] no]], tostring(t))

  stepKeys(m, 'N'); assertEq(1, e.l); assertEq(1, e.c)
end)

local UNDO_0 = '12345'
test('undo', function()
  local m = mockedModel(1, 9, UNDO_0)
  local e, t, s, sch = m.edit, m.term, m.statusEdit, m.searchEdit
  assertEq('12345', tostring(t))

  stepKeys(m, 'd f 3'); assertEq({1, 1}, {e.l, e.c})
    assertEq('345', tostring(t))
  stepKeys(m, 'u'); assertEq({1, 1}, {e.l, e.c})
    assertEq('12345', tostring(t))
  stepKeys(m, '^R'); assertEq({1, 1}, {e.l, e.c})
    assertEq('345', tostring(t))

  stepKeys(m, 'i a b c space ^J'); assertEq({1, 5}, {e.l, e.c})
    assertEq('abc 345', tostring(t))
  stepKeys(m, 'u');
    assertEq('345', tostring(t))
    assertEq({1, 1}, {e.l, e.c})
  stepKeys(m, '^R'); assertEq({1, 5}, {e.l, e.c})
    assertEq('abc 345', tostring(t))
    assertEq('abc 345', tostring(e.buf.gap))

  stepKeys(m, 'o 6 7 8 ^J'); assertEq({2, 4}, {e.l, e.c})
    assertEq('678', tostring(t))
    assertEq('abc 345\n678', tostring(e.buf.gap))

  stepKeys(m, 'u'); assertEq({1, 5}, {e.l, e.c})
    assertEq('abc 345', tostring(t))
    assertEq('abc 345', tostring(e.buf.gap))
  stepKeys(m, '^R'); assertEq({2, 4}, {e.l, e.c})
    assertEq('678', tostring(t))
    assertEq('abc 345\n678', tostring(e.buf.gap))

  stepKeys(m, 'g g $ x'); assertEq({1, 8}, {e.l, e.c})
    assertEq('abc 345678', tostring(e.buf.gap))
  stepKeys(m, 'u');       assertEq({1, 8}, {e.l, e.c})
    assertEq('abc 345\n678', tostring(e.buf.gap))
end)

local SPLIT = '1234567\n123'
test('splitV', function()
  local m = mockedModel(2, 20, SPLIT)
  local e1 = m.edit; assertEq(e1, m.view)
  stepKeys(m, 'space w V');
  assertEq(m.edit, e1) -- edit hasn't changed
  local w = m.view; assertEq(e1, w[2]) -- old edit is right
  local e2 = w[1]
  stepKeys(m, 'space w h'); assert(m.edit == e2) -- move, edit HAS changed
  stepKeys(m, 'space w l'); assertEq(m.edit, e1) -- go back

  assertEq([[
1234567  |1234567
123      |123]], tostring(m.term))
  stepKeys(m, 'space w d');
  assertEq(SPLIT, tostring(m.term))
  assert(m.edit == e2) -- edit HAS changed
end)

test('splitH', function()
  local m = mockedModel(5, 10, SPLIT)
  local e1 = m.edit; assertEq(e1, m.view)
  stepKeys(m, 'space w H');
  assertEq(m.edit, e1) -- edit hasn't changed
  local w = m.view; assertEq(e1, w[2]) -- old edit is bottom
  local e2 = w[1]
  stepKeys(m, 'space w k'); assert(m.edit == e2) -- move, edit has changed
  stepKeys(m, 'space w j'); assertEq(m.edit, e1) -- go back

  assertEq(SPLIT..'\n----------\n'..SPLIT, tostring(m.term))
  stepKeys(m, 'space w d');
  assertEq(SPLIT..'\n\n\n', tostring(m.term))
  assert(m.edit == e2) -- edit HAS changed
end)

test('splitStatus', function()
  local m, status, e1 = testModel(6, 10)
  assertEq([[
*123456789
1 This is 
2         
3         
----------
]], tostring(m.term))
  assertEq(e1, m.edit)

  -- first just go to status and back
  stepKeys(m, 'space w j'); assertEq(status, m.edit)
  stepKeys(m, 'space w k'); assertEq(e1,  m.edit)

  -- Split vertically then move around
  stepKeys(m, 'space w V'); assertEq(e1,     m.edit)
  stepKeys(m, 'space w j'); assertEq(status, m.edit)
  stepKeys(m, 'space w k'); assertEq(e1,     m.edit)
  stepKeys(m, 'space w X') -- unset chord status
  assertEq([[
*123|*1234
1 Th|1 Thi
2   |2    
3   |3    
----------
[unset] ch]], tostring(m.term))
end)
