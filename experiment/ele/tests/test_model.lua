METATY_CHECK = true

local pkg = require'pkglib'
local mty = require'metaty'
local ds  = require'ds'
local tostring = mty.tostring
local test, T.eq; ds.auto'civtest'

local ds = require'ds'
local buffer = require'rebuf.buffer'
local keys = require'ele.keys'
local model = require'ele.model'
local term = require'civix.term'
local T = require'ele.types'
local window = require'ele.window'
local data = require'ele.data'
local action = require'ele.action'
local A = action.Actions
local FakeTerm = require'ele.FakeTerm'

local add = table.insert

test('keypress', function()
  T.eq({'a', 'b'},  keys.parseKeys('a b'))
  T.eq({'a', '^B'}, keys.parseKeys('a ^b'))
  T.eq({'a', '^B'}, keys.parseKeys('a ^b'))
  T.eq({'return', '^B'}, keys.parseKeys('return ^b'))
end)

test('ctrl', function()
  T.eq('P', term.ctrlChar(16))
end)

local function mockInputs(inputs)
  return keys.parseKeys(inputs)
end

test('edit (only)', function()
  local t = FakeTerm(1, 4); assert(t)
  local e = T.Edit.new(nil, buffer.Buffer.new("1234567\n123\n12345\n"))
  e.tl, e.tc, e.th, e.tw = 1, 1, 1, 4
  e:draw(t, true); T.eq({'1234'}, e.canvas)
  e.th, e.tw = 2, 4; t:init(2, 4)
  e:draw(t, true)
  T.eq({'1234', '123'}, e.canvas)
  e.l, e.vl = 2, 2; e:draw(t, true)
  T.eq({'123', '1234'}, e.canvas)
  T.eq("123\n1234", tostring(t))
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
  T.eq(m:getBinding('^U'), {'up', times=15})
  local spc = m:getBinding('space')
  local win = assert(spc.w)
  T.eq(win.V, A.splitVertical)
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
  T.eq('1', m.inputCo())
  T.eq('2', m.inputCo())
  local e = m.edit;
  T.eq(1, e.l); T.eq(1, e.c)
  m:step(); T.eq({'1234'}, e.canvas)
            T.eq(1, e.l); T.eq(1, e.c)
  m:step(); T.eq({'8123'}, e.canvas)
            T.eq(1, e.l); T.eq(2, e.c)
  m:step(); T.eq({'8912'}, e.canvas)
            T.eq(1, e.l); T.eq(3, e.c)
end)

test('back', function()
  local m = mockedModel(
    1, 7, -- h, w
    '1234567',
    'i back back x')
  local e = m.edit;
  e.l, e.c = 1, 4 -- '4'
  m:step(); T.eq({'1234567'}, e.canvas) -- i
            T.eq(1, e.l); T.eq(4, e.c)
  m:step(); T.eq({'124567'}, e.canvas) -- back
            T.eq(1, e.l); T.eq(3, e.c)
  m:step(); T.eq({'14567'}, e.canvas)  -- back
            T.eq(1, e.l); T.eq(2, e.c)
  m:step(); T.eq({'1x4567'}, e.canvas)
            T.eq(1, e.l); T.eq(3, e.c)
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
  m:step(); T.eq(1, e.l); T.eq(3, e.c) -- k '3' (l 1)
  m:step(); T.eq(1, e.l); T.eq(4, e.c) -- l '4' (l 1)
  m:step(); T.eq(1, e.l); T.eq(3, e.c) -- h '3' (l 1)
  m:step(); T.eq(2, e.l); T.eq(3, e.c) -- j '3' (l 2)
  m:step(); T.eq(3, e.l); T.eq(3, e.c) -- j '3' (l 3)

  -- now test boundaries
  m.inputCo = ds.iterV(mockInputs('j $ k l')) -- down RIGHT up right
  m:step(); T.eq(3, e.l); T.eq(3, e.c) -- '\n' (l 3 EOF)
  m:step(); T.eq(3, e.l); T.eq(6, e.c) -- '\n' (l 3 EOF)
  m:step(); T.eq(2, e.l); T.eq(6, e.c) -- '\n' (l 2)
  m:step(); T.eq(2, e.l); T.eq(4, e.c) -- '\n' l2  (overflow set)

  -- now test insert on overflow
  -- up 3*right down insert-x-
  m.inputCo = ds.iterV(mockInputs('k l l l j i x'))  -- k l l l
  steps(m, 4); T.eq(1, e.l); T.eq(7, e.c); -- '7' (l 1)
               T.eq(1, e.vl)
  m:step();    T.eq(2, e.l); T.eq(7, e.c); -- j (l2 overflow)
               T.eq(2, e.vl)
  m:step();    T.eq(2, e.l); T.eq(7, e.c); -- i
  m:step();    T.eq({2, 5}, {e.l, e.c}) -- x
               T.eq({'123x'}, e.canvas)

  -- now test multi-movement
  stepKeys(m, '^J ^U'); T.eq({1, 5}, {e.l, e.c})
end)

local function splitSetup(m, kind)
  local eR = m.edit
  local eL = window.splitEdit(m.edit, kind)
  local w = eL.container
  assert(rawequal(w, m.view))
  assert(rawequal(w, eR.container))
  assert(rawequal(eR.buf, eL.buf))
  T.eq(eL, w[1]); T.eq(eR, w[2]);
  m:draw()
  return w, eL, eR
end

test('splitH', function()
  local m = mockedModel(
    5, 7, -- h, w
    '1234567\n123')
  local w, eL, eR = splitSetup(m, 'h')
  T.eq(7, w.tw)
  T.eq(7, eR.tw); T.eq(7, eL.tw)
  T.eq(2, eR.th); T.eq(2, eL.th)
  T.eq([[
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
  T.eq(20, w.tw)
  T.eq(10, eR.tw)
  T.eq(9,  eL.tw)
  T.eq([[
1234567  |1234567
123      |123]], tostring(m.term))
end)

test('splitEdit', function()
  local m = mockedModel(
    5, 7, -- h, w
    '1234567\n123')
  local w, eT, eB = splitSetup(m, 'h')
  stepKeys(m, 'i a b c')
  T.eq([[
abc1234
123
-------
abc1234
123]], tostring(m.term))
  -- go down twice (to EOF) then insert stuff
  stepKeys(m, '^J j j i 4 return b o t t o m')
  T.eq([[
abc1234
1234
-------
1234
bottom]], tostring(m.term))
    T.eq(3, eB.l); T.eq(7, eB.c)
end)


test('withStatus', function()
  local h, w = 9, 16
  local m, status, eTest = testModel(h, w)
  local t = m.term
  m:draw()
  T.eq(eTest, m.edit)
  T.eq(1, ds.indexOf(m.view, eTest))
  T.eq(2, ds.indexOf(m.view, status))
  T.eq(1, status.fh); T.eq(1, status:forceHeight())
  T.eq(1, m.view:forceDim('forceHeight', false))
  T.eq(7, m.view:period(9, 'forceHeight', 1))

  T.eq([[
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
  T.eq([[
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
  stepKeys(m, 'w'); T.eq(1, e.l); T.eq(e.c, 2) -- 'bc'
  stepKeys(m, 'w'); T.eq(1, e.l); T.eq(e.c, 4) -- '+'
  stepKeys(m, 'w'); T.eq(1, e.l); T.eq(e.c, 5) -- '12'
  stepKeys(m, 'w'); T.eq(1, e.l); T.eq(e.c, 8) -- '-'
  stepKeys(m, 'w'); T.eq(1, e.l); T.eq(e.c, 9) -- 'de'
  stepKeys(m, 'w'); T.eq(2, e.l); T.eq(e.c, 3) -- 'z' (next line)

  stepKeys(m, 'b'); T.eq(1, e.l); T.eq(e.c, 9) -- 'de'
  stepKeys(m, 'b'); T.eq(1, e.l); T.eq(e.c, 8) -- '-'
  stepKeys(m, 'b'); T.eq(1, e.l); T.eq(e.c, 5) -- '12'
  stepKeys(m, 'b'); T.eq(1, e.l); T.eq(e.c, 4) -- '+'
  stepKeys(m, 'b'); T.eq(1, e.l); T.eq(e.c, 2) -- 'bc'
  stepKeys(m, 'b'); T.eq(1, e.l); T.eq(e.c, 1) -- SOL
  stepKeys(m, 'j b'); T.eq(1, e.l); T.eq(e.c, 9)  -- 'de'
end)

------------
-- Test D C modline
local MODLINE_0 = '12345\n8909876'
test('modLine', function()
  local m = mockedModel(2, 8, MODLINE_0)
  local e, t = m.edit, m.term
  e.l, e.c = 1, 1
  stepKeys(m, 'A 6 7 ^J'); T.eq(1, e.l); T.eq(8, e.c)
  T.eq('1234567\n8909876', tostring(t))
  stepKeys(m, 'h h D'); T.eq(1, e.l); T.eq(6, e.c)
    T.eq(MODLINE_0, tostring(t))
  stepKeys(m, 'h h C'); T.eq(1, e.l); T.eq(4, e.c)
    T.eq('insert', m.mode)
  stepKeys(m, 'a b c ^J'); T.eq(1, e.l); T.eq(7, e.c)
    T.eq('123abc\n8909876', tostring(t))
  stepKeys(m, '0'); T.eq(1, e.l); T.eq(1, e.c)
  stepKeys(m, '$'); T.eq(1, e.l); T.eq(7, e.c)
  stepKeys(m, 'o h i ^J'); T.eq(2, e.l); T.eq(3, e.c)
    T.eq('123abc\nhi', tostring(t))
  stepKeys(m, 'k 0 x x'); T.eq(1, e.l); T.eq(1, e.c)
    T.eq('3abc\nhi', tostring(t))
end)

------------
-- Test d delete
local DEL = '12 34+56\n78+9'
test('deleteChain', function()
  local m = mockedModel(1, 8, '12 34 567')
  local e, t = m.edit, m.term; e.l, e.c = 1, 1
  stepKeys(m, 'd w'); T.eq(1, e.l); T.eq(1, e.c)
    T.eq('34 567', tostring(t))
  stepKeys(m, '2 d w'); T.eq(1, e.l); T.eq(1, e.c)
     T.eq('', tostring(t))
  e.buf.gap:insert(DEL, 1, 1)
  t:init(2, 8); m:draw(); T.eq(DEL, tostring(t))
  stepKeys(m, 'l j d d');
     T.eq(1, e.l); T.eq(2, e.c)
     T.eq('12 34+56\n', tostring(t))
  stepKeys(m, 'f 4');
    T.eq(1, e.l); T.eq(5, e.c)
  stepKeys(m, 'd f 5');
     T.eq(1, e.l); T.eq(5, e.c)
     T.eq('12 356\n', tostring(t))

  stepKeys(m, 'd F 2');
    T.eq(1, e.l); T.eq(2, e.c)
    T.eq('156\n', tostring(t))
  stepKeys(m, 'g g d G')
    T.eq(1, e.l); T.eq(1, e.c)
    T.eq('\n', tostring(t))
end)

------------
-- Test c delete
test('change', function()
  local m = mockedModel(1, 12, '12 34 567')
  local e, t = m.edit, m.term; e.l, e.c = 1, 4
  stepKeys(m, 'c w'); T.eq(1, e.l); T.eq(4, e.c)
    T.eq('12 567', tostring(t))
    T.eq('insert', m.mode)
  stepKeys(m, 'a b c space ^J'); T.eq(1, e.l); T.eq(8, e.c)
    T.eq('12 abc 567', tostring(t))
  stepKeys(m, 'r Z'); T.eq(1, e.l); T.eq(8, e.c)
    T.eq('12 abc Z67', tostring(t))
end)

------------
-- Test /search
local SEARCH_0 = '12345\n12345678\nabcdefg'
test('modLine', function()
  local m = mockedModel(3, 9, SEARCH_0)
  local e, t, s, sch = m.edit, m.term, m.statusEdit, m.searchEdit
  e.l, e.c = 1, 1
  stepKeys(m, '/ 3 4'); T.eq(1, e.l); T.eq(1, e.c)
  T.eq([[
12345
---------
34]], tostring(t))
  stepKeys(m, 'return'); T.eq(1, e.l); T.eq(3, e.c)
    T.eq(SEARCH_0, tostring(t))
  stepKeys(m, '/ 2 3 4'); T.eq(1, e.l); T.eq(3, e.c)
  T.eq([[
12345
---------
234]], tostring(t))
  stepKeys(m, 'return'); T.eq(2, e.l); T.eq(2, e.c)
    T.eq(SEARCH_0, tostring(t))

  m:showStatus(); m:draw()
  T.eq([[
12345678
---------
]], tostring(t))

  stepKeys(m, '/ 1 2 3')
  T.eq(m.view[1], e)
  T.eq(m.view[2][1], sch)
  T.eq(m.view[2][2], s)
  T.eq(1, m.view[2]:forceHeight())
  T.eq({1, 4}, {s.th, s.tw})
  T.eq({2, 2, 1, 9}, {e.l, e.c, e.th, e.tw})
  T.eq([[
12345678
---------
123 |]], tostring(t))
  stepKeys(m, 'return')
T.eq([[
12345678
---------
[find] no]], tostring(t))

  stepKeys(m, 'N'); T.eq(1, e.l); T.eq(1, e.c)
end)

local UNDO_0 = '12345'
test('undo', function()
  local m = mockedModel(1, 9, UNDO_0)
  local e, t, s, sch = m.edit, m.term, m.statusEdit, m.searchEdit
  T.eq('12345', tostring(t))

  stepKeys(m, 'd f 3'); T.eq({1, 1}, {e.l, e.c})
    T.eq('345', tostring(t))
  stepKeys(m, 'u'); T.eq({1, 1}, {e.l, e.c})
    T.eq('12345', tostring(t))
  stepKeys(m, '^R'); T.eq({1, 1}, {e.l, e.c})
    T.eq('345', tostring(t))

  stepKeys(m, 'i a b c space ^J'); T.eq({1, 5}, {e.l, e.c})
    T.eq('abc 345', tostring(t))
  stepKeys(m, 'u');
    T.eq('345', tostring(t))
    T.eq({1, 1}, {e.l, e.c})
  stepKeys(m, '^R'); T.eq({1, 5}, {e.l, e.c})
    T.eq('abc 345', tostring(t))
    T.eq('abc 345', tostring(e.buf.gap))

  stepKeys(m, 'o 6 7 8 ^J'); T.eq({2, 4}, {e.l, e.c})
    T.eq('678', tostring(t))
    T.eq('abc 345\n678', tostring(e.buf.gap))

  stepKeys(m, 'u'); T.eq({1, 5}, {e.l, e.c})
    T.eq('abc 345', tostring(t))
    T.eq('abc 345', tostring(e.buf.gap))
  stepKeys(m, '^R'); T.eq({2, 4}, {e.l, e.c})
    T.eq('678', tostring(t))
    T.eq('abc 345\n678', tostring(e.buf.gap))

  stepKeys(m, 'g g $ x'); T.eq({1, 8}, {e.l, e.c})
    T.eq('abc 345678', tostring(e.buf.gap))
  stepKeys(m, 'u');       T.eq({1, 8}, {e.l, e.c})
    T.eq('abc 345\n678', tostring(e.buf.gap))
end)

local SPLIT = '1234567\n123'
test('splitV', function()
  local m = mockedModel(2, 20, SPLIT)
  local e1 = m.edit; T.eq(e1, m.view)
  stepKeys(m, 'space w V');
  T.eq(m.edit, e1) -- edit hasn't changed
  local w = m.view; T.eq(e1, w[2]) -- old edit is right
  local e2 = w[1]
  stepKeys(m, 'space w h'); assert(m.edit == e2) -- move, edit HAS changed
  stepKeys(m, 'space w l'); T.eq(m.edit, e1) -- go back

  T.eq([[
1234567  |1234567
123      |123]], tostring(m.term))
  stepKeys(m, 'space w d');
  T.eq(SPLIT, tostring(m.term))
  assert(m.edit == e2) -- edit HAS changed
end)

test('splitH', function()
  local m = mockedModel(5, 10, SPLIT)
  local e1 = m.edit; T.eq(e1, m.view)
  stepKeys(m, 'space w H');
  T.eq(m.edit, e1) -- edit hasn't changed
  local w = m.view; T.eq(e1, w[2]) -- old edit is bottom
  local e2 = w[1]
  stepKeys(m, 'space w k'); assert(m.edit == e2) -- move, edit has changed
  stepKeys(m, 'space w j'); T.eq(m.edit, e1) -- go back

  T.eq(SPLIT..'\n----------\n'..SPLIT, tostring(m.term))
  stepKeys(m, 'space w d');
  T.eq(SPLIT..'\n\n\n', tostring(m.term))
  assert(m.edit == e2) -- edit HAS changed
end)

test('splitStatus', function()
  local m, status, e1 = testModel(6, 10)
  T.eq([[
*123456789
1 This is 
2         
3         
----------
]], tostring(m.term))
  T.eq(e1, m.edit)

  -- first just go to status and back
  stepKeys(m, 'space w j'); T.eq(status, m.edit)
  stepKeys(m, 'space w k'); T.eq(e1,  m.edit)

  -- Split vertically then move around
  stepKeys(m, 'space w V'); T.eq(e1,     m.edit)
  stepKeys(m, 'space w j'); T.eq(status, m.edit)
  stepKeys(m, 'space w k'); T.eq(e1,     m.edit)
  stepKeys(m, 'space w X') -- unset chord status
  T.eq([[
*123|*1234
1 Th|1 Thi
2   |2    
3   |3    
----------
[unset] ch]], tostring(m.term))
end)
