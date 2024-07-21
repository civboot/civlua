-- Test display functionality (not mutation)

local T = require'civtest'
local mty = require'metaty'
local ds, lines = require'ds', require'lines'
local log = require'ds.log'
local etest = require'ele.testing'
local edit = require'ele.edit'
local Session = require'ele.Session'
local Buffer = require'rebuf.buffer'.Buffer
local Fake = require'vt100.testing'.Fake
local path = require'ds.path'

local str = mty.tostring
local aeq = T.assertEq

local _CWD = CWD
CWD = path.abs(ds.srcdir()) -- override global

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
  'th', th=3, 'tw', tw=20,
  'dat', 'open [path]',
  's [Session]',
}
getmetatable(Test).__call = function(Ty, t)
  t = mty.construct(Ty, t)
  t.s = t.s or Session:test(); local ed = t.s.ed
  ed.display = Fake{h=t.th, w=t.tw}
  T.asyncTest(assert(t[1], 'need name'), function()
    if t.dat then
      lines.inset(ed.edit.buf.dat, t.dat, 1)
    elseif t.open then ed:open(t.open) end
    t.s:handleEvents()
    assert(t[2], 'need [2]=fn')(t)
    aeq(log.LogTable{}, ed.error)
    ed.run = false
  end)
end

Test{'session', dat='', function(tst)
  local s, ed, e = tst.s, tst.s.ed, tst.s.ed.edit
  local b, t = ed.edit.buf, ed.display
  aeq('command', ed.mode)
  aeq('\n\n', str(t))

  s:play'Z' -- unknown
    aeq(1, #ed.error)
    T.assertMatch('unbound chord: Z', ed.error[1].msg)
  ds.clear(ed.error)

  s:play'i'
    aeq('insert', ed.mode) -- next mode
    aeq(nil, ed.ext.keys.next) -- selected in keyinput
  aeq(log.LogTable{}, ed.error)

  s:play'9 space 8'; ed:draw()
    aeq('9 8', b.dat[1])
    aeq('9 8\n\n', str(t))
  aeq(log.LogTable{}, ed.error)

  s:play'space 7 return 6'
    aeq('9 8 7\n6\n', str(t))
end}

Test{'move', dat=LINES3, function(tst)
  local s, ed, e = tst.s, tst.s.ed, tst.s.ed.edit
  aeq(3, #e.buf)
  aeq('command', ed.mode)
  aeq('\n\n', str(ed.display))

  s:play'' -- draw
    aeq('1 3 5 7 9\n 2 4 6\n', str(ed.display))

  s:play'j';   aeq({2, 1}, {e.l, e.c})
    aeq(LINES3, str(ed.display))
  s:play'2 k'; aeq({1, 1}, {e.l, e.c})
  s:play'$';   aeq({1, 9}, {e.l, e.c})
  s:play'j';   aeq({2, 7}, {e.l, e.c})
    aeq(LINES3, str(ed.display))

  s:play'0';   aeq({2, 1}, {e.l, e.c})
  s:play'2 w'; aeq({2, 4}, {e.l, e.c})
  s:play'b';   aeq({2, 2}, {e.l, e.c})
  s:play'l ^'; aeq({2, 2}, {e.l, e.c})
end}

Test{'backspace', dat=LINES3, function(tst)
  local s, ed, e = tst.s, tst.s.ed, tst.s.ed.edit
  local b = e.buf
  s:play'l l';    aeq({1, 3}, {e.l, e.c})
  s:play'i back'; aeq({1, 2}, {e.l, e.c})
    aeq('13 5 7 9', b[1])
  aeq('13 5 7 9\n 2 4 6\n', str(ed.display))
end}

Test{'open', open=SMALL, th=9, tw=30, function(tst)
  local s, ed, e = tst.s, tst.s.ed, tst.s.ed.edit
  local b, BID = e.buf, 2
  aeq(b.id, BID)
  aeq(0, #ed.buffers[1].tmp) -- was temporary and was closed
  aeq(SMALL, b.dat.path)
  s:play'' -- draws
    aeq('-- a small lua file for tests', b[1])
    aeq(ds.readPath(SMALL), str(ed.display))
  s:play'd f space'
    aeq('a small lua file for tests', b[1])
  e = ed:open(SMALL)
    aeq(b.id, BID)
    assert(rawequal(b, e.buf), 'buf is new')
    aeq('a small lua file for tests', b[1]) -- no change to contents
end}

Test{'nav', dat='', function(tst)
  -- local s, ed, e = tst.s, tst.s.ed, tst.s.ed.edit
  -- local b, BID = e.buf, 2
  -- s:play'space f space' -- listCWD
  --   aeq(BID, b.id) -- opened new buffer
end}

CWD = _CWD
