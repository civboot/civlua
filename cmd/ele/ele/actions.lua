-- Actions builtin plugin
local M = mod and mod'ele.actions' or {}
local mty = require'metaty'
local log = require'ds.log'
local motion = require'rebuf.motion'
local et = require'ele.types'

local push, pop = table.insert, table.remove
local sfmt = string.format
local callable = mty.callable

----------------------------------
-- KEYBINDINGS

-- keyinput action.  This handles actual user keyboard inputs as well as
-- hotkey/etc.
--
-- The basic architecture of keys.lua is that the Keys object holds all
-- state necessary for determining user intent across a chord of keys,
-- which are pressed in sequence. Typically, these end with the binding
-- generating an event when all keys are gathered.
M.keyinput = function(ed, ev, evsend)
  local ki = assert(ev[1])
  local K, err = ed.ext.keys
  log.info('action: %q mode=%s keep=%s', ev, ed.mode, K.keep)
  if K.keep then K.keep = nil
  else
    K.chord, K.event = {}, {}
    K.next = ed.modes[ed.mode]
  end
  mty.eprint('?? K.next', K.next)
  local nxt = callable(K.next) and K.next
    or rawget(K.next, ki) or ed.modes[ed.mode].fallback
  if not callable(nxt) then
    assert(type(nxt) == 'table')
    K.next, K.keep = nxt, true
    return
  end
  push(K.chord, ki)
  log.info(' + binding=%q chord=%q', nxt, K.chord)
  local ev = nxt(K)
  if ev then
    evsend:pushLeft(ev)
    if ev.mode then
      err = et.checkMode(ed, ev.mode); if err then
        error(sfmt('%s -> event has invalid mode: %s', n, ev.mode))
      end
      ed.mode = ev.mode
    end
  end
  err = K:check(ed); if err then
    K.keep = nil
    error(sfmt('bindings.%s(keys) -> invalid keys: %s', n, err))
  end
end
M.hotkey = keyinput

----------------------------------
-- UTILITY

-- merge action
-- directly merges ed with event (action key removed)
M.merge = function(ed, ev)
  ev.action = nil; ds.merge(ed, ev)
end

-- chain: push multiple events to the FRONT, effectively
--   replacing this action with it's children.
-- Note: supports times
M.chain = function(ed, ev, evsend)
  for _=1,ev.times or 1 do evsend:extendLeft(ev) end
end

----------------------------------
-- MOVE
-- This defines the move action
local DOMOVE = {
  lines    = function(e, _, ev) e.l = e.l + ev.lines end,
  sol      = function(e, line) e.c = line:find'%S' or 1                end,
  eol      = function(e, line) e.c = #line                             end,
  forword  = function(e, line)
    e.c = motion.forword(line, e.c) or (e.c + 1)
  end,
  backword = function(e, line)
    e.c = motion.backword(line, e.c) or (e.c + 1)
  end,
  find = function(e, line, ev)
    e.c = line:find(ev.find, e.c, true) or e.c
  end,
  findback = function(e, line, ev)
    e.c = motion.findBack(line, ev.findback, e.c, true) or e.c
  end,
}
local domove = function(e, ev)
  local fn = ev.move and DOMOVE[ev.move]
  if fn      then fn(e, e.buf[e.l], ev) end
  if ev.cols then e.c = e.c + ev.cols   end
  if ev.off  then e:offset(ev.off)      end
end

-- move action
--
-- set move key to one of:
--   lines: move set number of lines (set lines = +/- int)
--   forword, backword: go to next/prev word
--   sol, eol: go to start/end of line
--   find, findback: find character forwards/backwards (set find/findback key)
--
-- these can additionally be set and will be done in order:
--   cols, off: move cursor by columns/offset (positive or negative)
--
-- Supports: times
M.move = function(ed, ev)
  local e = ed.edit
  for _=1,ev.times or 1 do domove(e, ev) end
  e.l = math.min(#e.buf, e.l); e.c = e:boundCol(e.c)
end

----------------------------------
-- MODIFY

-- insert action
--
-- this inserts text at the current position.
M.insert = function(ed, ev)
  local e = ed.edit; e:changeStart()
  e:insert(string.rep(assert(ev[1]), ev.times or 1))
end

-- remove movement action
--
-- This is always tied with a movement (except below).
-- It performs the movement and then uses the new location
-- as the "end"
--
-- Exceptions:
-- * lines=0 removes a single line (also supports times)
M.remove = function(ed, ev)
  local e = ed.edit; e:changeStart()
  if ev.lines == 0 then
    local t = ev.times; local l2 = (t and (t - 1)) or 0
    log.info('remove lines(0) %s:%s', e.l, e.l + l2)
    return e:remove(e.l, e.l + l2)
  end
  if ev.move == 'forword' then ev.cols = -1 end
  local l, c = e.l, e.c
  M.move(ed, ev)
  log.info('remove moved: %s.%s -> %s.%s', l, c, e.l, e.c)
  if ev.lines then e:remove(l, e.l)
  else             e:remove(l, c, e.l, e.c) end
  l, c = motion.topLeft(l, c, e.l, e.c)
  e.l = math.min(#e.buf, l); e.c = e:boundCol(c)
end

return M
