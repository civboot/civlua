-- Test display functionality (not mutation)

local T = require'civtest'
local CT = require'civtest'
local mty = require'metaty'
local fmt = require'fmt'
local ds, lines = require'ds', require'lines'
local pth = require'ds.path'
local log = require'ds.log'
local etest = require'ele.testing'
local edit = require'ele.edit'
local Session = require'ele.Session'
local et = require'ele.types'
local Buffer = require'lines.buffer'.Buffer
local Fake = require'vt100.testing'.Fake
local path = require'ds.path'
local ixt = require'civix.testing'

local _CWD = CWD
CWD = path.abs(ds.srcdir()) -- override global

local SC = '[mode:command]'
local SI = '[mode:insert]'
local SMALL = CWD..'small.lua'
local LINES3 =
  '1 3 5 7 9\n'
..' 2 4 6\n'
..''

local y = function(v) coroutine.yield(v or true) end

local function run(s)
  while (#s.keys + #s.events > 0) do coroutine.yield(true) end
end

-- Test{th=5, ..., 'name', function(test) ed = test.s.ed; ... end}
local Test = mty.record'session.Test' {
  'th', th=4, 'tw', tw=20,
  'dat', 'open [path]',
  's [Session]',
}
getmetatable(Test).__call = function(Ty, t)
  local path = ds.srcloc(1)
  t = mty.construct(Ty, t)
  t.s = t.s or Session:test{}; local ed = t.s.ed
  assert(ed.view == ed.edit)
  ed.display = Fake{h=t.th, w=t.tw}
  local name = assert(t[1], 'need name')
  print('## test_session.Test', name)
  local testFn = function()
    if t.dat then
      lines.inset(ed.edit.buf.dat, t.dat, 1)
    elseif t.open then ed:open(t.open) end
    t.s:handleEvents()
    assert(t[2], 'need [2]=fn')(t)
    T.eq(log.LogTable{}, ed.error)
    ed.run = false
  end
  ixt.runAsyncTest(function() T.runTest(name, testFn, path) end)
end

Test{'session', dat='', function(tst)
  local s, ed, e = tst.s, tst.s.ed, tst.s.ed.edit
  local b, t = ed.edit.buf, ed.display
  T.eq('command', ed.mode)
  T.eq('\n\n\n', fmt(t))

  s:play'Z' -- unknown
    T.eq(1, #ed.error)
    T.matches('unbound chord: Z', fmt(ed.error[1]))
  ds.clear(ed.error)

  s:play'i'
    T.eq('insert', ed.mode) -- next mode
    T.eq(nil, ed.ext.keys.next) -- selected in keyinput
  T.eq(log.LogTable{}, ed.error)

  s:play'9 space 8'; ed:draw()
    T.eq('9 8', b.dat[1])
    T.eq(SI..'\n9 8\n\n', fmt(t))
  T.eq(log.LogTable{}, ed.error)

  s:play'space 7 enter 6'
    T.eq(SI..'\n9 8 7\n6\n', fmt(t))
end}

Test{'move', dat=LINES3, function(tst)
  local s, ed, e = tst.s, tst.s.ed, tst.s.ed.edit
  T.eq(3, #e.buf)
  T.eq('command', ed.mode)
  T.eq('\n\n\n', fmt(ed.display))

  s:play'' -- draw
    T.eq(SC..'\n1 3 5 7 9\n 2 4 6\n', fmt(ed.display))

  s:play'j';   T.eq({2, 1}, {e.l, e.c})
    T.eq(SC..'\n'..LINES3, fmt(ed.display))
  s:play'2 k'; T.eq({1, 1}, {e.l, e.c})
  s:play'$';   T.eq({1, 9}, {e.l, e.c})
  s:play'j';   T.eq({2, 7}, {e.l, e.c})
    T.eq(SC..'\n'..LINES3, fmt(ed.display))

  s:play'0';   T.eq({2, 1}, {e.l, e.c})
  s:play'2 w'; T.eq({2, 4}, {e.l, e.c})
  s:play'b';   T.eq({2, 2}, {e.l, e.c})
  s:play'l ^'; T.eq({2, 2}, {e.l, e.c})
end}

Test{'backspace', dat=LINES3, function(tst)
  local s, ed, e = tst.s, tst.s.ed, tst.s.ed.edit
  local b = e.buf
  s:play'l l';    T.eq({1, 3}, {e.l, e.c})
  s:play'i back'; T.eq({1, 2}, {e.l, e.c})
    T.eq('13 5 7 9', b:get(1))
  T.eq(SI..'\n13 5 7 9\n 2 4 6\n', fmt(ed.display))
end}

local SMALL_1 = '\n'..[[
 0-- a small lua file for test
 1local M = {}
 2
 3M.main = function()
 4  print'hello world'
 5end
 6
| small.lua:1.1 (b#3) ========]]
Test{'open', open=SMALL, th=9, tw=30, function(tst)
  local s, ed, e = tst.s, tst.s.ed, tst.s.ed.edit
  local b, BID = e.buf, 3
  T.eq(b.id, BID)
  T.eq(0, #ed.buffers[1].tmp) -- was temporary and was closed
  T.eq(SMALL, b.dat.path)
  s:play'' -- draws
    T.eq('-- a small lua file for tests', b:get(1))
    T.eq(SC..SMALL_1, fmt(ed.display))
  s:play'd f space'
    T.eq('a small lua file for tests', b:get(1))
  e = ed:open(SMALL)
    T.eq(b.id, BID)
    assert(rawequal(b, e.buf), 'buf is new')
    T.eq('a small lua file for tests', b:get(1)) -- no change to contents
end}

-- Test{'nav', dat='', function(tst)
--   local s, ed, e = tst.s, tst.s.ed, tst.s.ed.edit
--   local b, BID = e.buf, 2
--   s:play'space f space' -- listCWD
--     T.eq(BID, b.id) -- opened new buffer
-- end}


local SPLIT_1 = '\n'..[[
 0-- a small lua file for te 0-- a small lua file for test
 1local M = {}               1local M = {}
 2                           2
| small.lua:1.1 (b#3) ======| small.lua:1.1 (b#3) ========]]
local SPLIT_2 = '\n'..[[
 0-- a small lua file for te 1-- a small lua file for test
 1local M = {}               0local M = {}
 2                           1
| small.lua:1.1 (b#3) ======| small.lua:2.7 (b#3) ========]]

Test{'window', open=SMALL, th=5, tw=60, function(tst)
  local s, ed, e = tst.s, tst.s.ed, tst.s.ed.edit
  local b, BID = e.buf, 3
  T.eq(b.id, BID)
  T.eq(SMALL, b.dat.path)
  s:play'g L'
    T.eq(SC..SPLIT_1, fmt(ed.display))
    T.eq(et.VSplit, mty.ty(ed.view))
    T.eq(e, ed.view[1])
    T.eq(ed.edit, ed.view[2])
    assert(e ~= ed.edit)

  local sp = ed.view
  local e1, e2 = sp[1], sp[2]
  s:play'j f M'
    T.eq({1,1}, {e1.l,e1.c})
    T.eq({2,7}, {e2.l,e2.c})
    T.eq(SC..SPLIT_2, fmt(ed.display))
end}


CWD = _CWD
