-- Actions builtin plugin
local M = mod and mod'ele.actions' or {}
local mty = require'metaty'
local fmt = require'fmt'
local ds = require'ds'
local log = require'ds.log'
local lines = require'lines'
local motion = require'lines.motion'
local et = require'ele.types'

local push, pop = table.insert, table.remove
local concat    = table.concat
local sfmt      = string.format
local min, max  = math.min, math.max
local callable = mty.callable
local try = ds.try

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
  local mode = ed.modes[ed.mode]; local fallback = mode.fallback
  -- note: ki=key-input
  local ki, K, err = assert(ev[1], 'missing key'), ed.ext.keys
  if K.keep then K.keep = nil
  else           K.chord, K.event, K.next = {}, nil, nil end
  push(K.chord, ki)
  log.info('keyinput %q mode=%s', K.chord, ed.mode)
  local nxt = K.next
  if nxt then
    local getb = type(nxt) == 'table' and mty.getmethod(nxt, 'getBinding')
    if getb then nxt = getb(nxt, ki) end
  else
    local emode = ds.getp(ed, {'edit', 'modes', ed.mode, ki})
    nxt = emode and rawget(emode, ki)
       or rawget(mode, ki)
       or emode and rawget(emode, 'fallback')
  end
  nxt = nxt or fallback
  local ok, ev
  if type(nxt) == 'table' and not getmetatable(nxt) then
    log.info(' + keyinput plain ev %q (%q)', K.chord, nxt)
    ok, ev = true, ds.copy(nxt)
  elseif callable(nxt) then
    log.info(' + keyinput calling %q (%q)', K.chord, nxt)
    ok, ev = try(nxt, K)
    if not ok then
      return ed.error('%q (%s) failed: %q',
                      nxt, concat(K.chord, ' '), ev)
    end
  elseif mty.getmethod(nxt, 'getBinding') then
    K.next, K.keep = nxt, true
    return -- wait till next key
  else
    K.keep = nil
    fmt.errorf('%q is neither callable, plain table or KeyBindings',
      K.chord)
  end
  if ev then
    log.info(' --> %q', ev)
    evsend:pushLeft(ev)
  end
  err = K:check(ed); if err then
    K.keep = nil
    ed.error('%s -> invalid keys: %s', ki, err)
  end
end
M.hotkey = M.keyinput

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

-- TODO: decide how I want to do replace mode
--   probably need an ed:switchMode() function and use
--   ed.ext.mode table which is cleared on each switch.
--   Then insert.default just checks ext.mode.replace
--   to decide to replace instead of insert.
-- M.replacemode = function(ed)
--   ed.mode = 'insert'; ed.replace = true
-- end

----------------------------------
-- MOVE
-- This defines the move action
local DOMOVE = {
  lines = function(e, _, ev) e.l = e.l + ev.lines end,
  -- start/end of line/text
  sol = function(e, line) e.c = 1                  end,
  sot = function(e, line) e.c = line:find'%S' or 1 end,
  eol = function(e, line) e.c = #line              end,
  eot = function(e, line) e.c = line:find'.*%S%s*' or #line end,
  -- move by word
  forword  = function(e, line)
    e.c = motion.forword(line, e.c) or (e.c + 1)
  end,
  backword = function(e, line)
    e.c = motion.backword(line, e.c) or (e.c + 1)
  end,
  -- search for character
  find = function(e, line, ev)
    e.c = line:find(ev.find, e.c, true) or e.c
  end,
  findback = function(e, line, ev)
    e.c = motion.findBack(line, ev.findback, e.c, true) or e.c
  end,
}
local domove = function(e, ev)
  local fn = ev.move and DOMOVE[ev.move]
  if fn      then fn(e, e.buf:get(e.l), ev)       end
  if ev.cols then e.c = e.c + ev.cols         end
  if ev.off  then e.l, e.c = e:offset(ev.off) end
  if ev.rows then e.l = e.l + ev.rows         end
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
  log.trace('move %q [start %s.%s]', ev, e.l, e.c)
  for _=1,ev.times or 1 do domove(e, ev) end
  e.l, e.c = e:boundLC(e.l, e.c)
  ed:handleStandard(ev)
end

----------------------------------
-- MODIFY

-- insert action
--
-- this inserts text at the current position.
M.insert = function(ed, ev)
  local e = ed.edit; e:changeStart()
  e:insert(string.rep(assert(ev[1]), ev.times or 1))
  ed:handleStandard(ev)
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
    e:remove(e.l, e.l + l2)
    return ed:handleStandard(ev)
  end
  if ev.move == 'forword' then ev.cols = ev.cols or -1 end
  local l, c = e.l, e.c + (ev.cols1 or 0)
  M.move(ed, ev)
  local l, c, l2, c2 = lines.sort(l, c, e.l, e.c)
  log.info('remove %q: %s.%s -> %s.%s', ev, l, c, l2, c2)
  if ev.lines then e:remove(l, l2)
  else             e:remove(l, c, l2, c2) end
  l, c = motion.topLeft(l, c, l2, c2)
  e.l = math.min(#e.buf, l); e.c = e:boundCol(c)
  ed:handleStandard(ev)
end

----------------------------------
-- NAV

M.expandDir = function(ed, ev, evsend)
  local e = ed.edit
  local line = 
  log.trace('expandDir', ev, e.l, e.c)

end

M.nav = function(ed, ev, evsend)
  local to = assert(ev[1], 'nav: must provide index 1 for to')
  to = fmt.assertf(ed.ext.nav[to], 'nav: invalid to=%q', to)
  to(ed, ev, evsend)
  ed:handleStandard(ev)
end

return M
