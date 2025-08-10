-- Actions builtin plugin
local M = mod and mod'ele.actions' or {}
local mty = require'metaty'
local fmt = require'fmt'
local ds = require'ds'
local pth = require'ds.path'
local log = require'ds.log'
local lines = require'lines'
local motion = require'lines.motion'
local ix     = require'civix'
local et = require'ele.types'

local push, pop = table.insert, table.remove
local concat    = table.concat
local sfmt      = string.format
local srep, sconcat = string.rep, string.concat
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

M.nav = mod and mod'ele.actions.nav' or {};
local nav = M.nav

nav.getFocus = function(line)
  return line:match'^%-?([.~]?/[^\n]*)'
end
nav.getEntry = function(line) --> (indent, kind, entry)
  local i, k, e = line:match'^(%s+)([*+-])%s*([^\n]+)'
  if not i then return end
  return i, k, e:match'^%./' and e:sub(3) or e
end
local getFocus, getEntry = nav.getFocus, nav.getEntry

--- Find the parent of current path entry
--- if isFocus the entry will be the focus (and ind will be 0)
nav.findParent = function(b, l) --> linenum, line
  local line = b:get(l);
  if getFocus(line) then return l, line, true  end
  local ind = getEntry(line); if not ind then return end
  ind = #ind
  for l = l, 1, -1 do
    local line = b:get(l);
    if getFocus(line) then return l, line, true  end
    local i = getEntry(line); if not i then return end
    if #i < ind       then return l, line, false end
  end
end

--- Find the focus path line num (i.e. the starting directory)
nav.findFocus = function(b, l) --> linenum, line
  for l=l,1,-1 do
    local line = b:get(l)
    if getFocus(line)     then return l, line end
    if not getEntry(line) then return end
  end
end

--- Find the last line of the focus's entities (or itself).
--- invariant: line l is an entry or focus.
nav.findEnd = function(b, l) --> linenum, line
  for l=l+1,#b do
    local line = b:get(l);
    if not getEntry(line) then return l - 1 end
  end
end

--- Find the view (focusLineNum, endLineNum, focusLine)
nav.findView = function(b, l) --> (fln, eln, fline)
  local fl, fline = nav.findFocus(b, l); if not fl then return end
  return fl, assert(nav.findEnd(b, l)), fline
end

--- Walk up the parents, getting the full path.
--- If not an entry, try to find the path from the column.
nav.getPath = function(b, l,c) --> string
  local ln = b:get(l); local path, ind
  local focus   = getFocus(ln); if focus then return focus  end
  local i, _, e = getEntry(ln); if not i then goto nonentry end
  path, ind = {e}, #i

  -- Scan up, adding entries with less indent to path.
  for l = l-1, 1, -1 do
    local line = b:get(l)
    focus = getFocus(line); if focus then
      push(path, focus)
      return pth.concat(ds.reverse(path))
    end
    i, _, e = getEntry(line); if not i then break end
    if #i < ind then push(path, e); ind = #i end
  end
  ::nonentry::
  if motion.pathKind(ln:sub(c,c)) ~= 'path' then return end
  local si, ei = motion.getRange(ln, c, motion.pathKind)
  return ln:sub(si,ei)
end

nav.findEntryEnd = function(b, l) --> linenum
  local ind = getEntry(b:get(l)); if not ind then return end
  ind = #ind
  for l=l+1, #b do
    local i = getEntry(b:get(l))
    if not i or #i <= ind then return l-1 end
  end
end

nav.backFocus = function(b, l)
  local fl,fe = nav.findView(b, l)
  if not fl then return end
  if fe > fl then b:remove(fl+1, fe) end
end

--- Go backwards on the entry, returning the new line
--- For focus, this will go back one component.
--- For entry, this will collapse parent (and move to it).
nav.backEntry = function(b, l) --> ln
  ::start::
  local le = nav.findEntryEnd(b, l)
  if not le then
    nav.backFocus(b, l)
    return l
  end
  if l == le then
    l = nav.findParent(b, l)
    goto start
  end
  if le > l then b:remove(l+1, le) end
  return l
end

nav.expandEntry = function(b, l, ls) --> numEntries
  local entries = ls(nav.getPath(b, l))
  if #entries == 0 then return end
  local ind = #(getEntry(b:get(l)) or '')
  for i, e in ipairs(entries) do
    entries[i] = sconcat('', srep(' ',ind+2), '* ', e)
  end
  push(entries, '')
  b:insert(concat(entries, '\n'), l+1)
  return #entries
end

nav.doBack = function(b, l, times)
  for _=1,times do
    local nl = nav.backEntry(b, l); if l == nl then break end
    l = nl
  end
end

nav.doExpand = function(b, l, times, ls)
  if not pth.isDir(getEntry(b:get(l))) then return end
  ls = ls or ix.dir
  local numEntries = nav.expandEntry(b, l, ls)
  times = times - 1; if times <= 0 then return end
  for l=l+1, l+numEntries do nav.doExpand(b, l, times, ls) end
end

--- go to path at l,c. If op=='create' then create the path
nav.goPath = function(ed, create)
  local e = ed.edit
  local p = nav.getPath(e.buf, e.l,e.c)
  if p then
    local b = ed:getBuffer(p)
    if b then return ed:editSwap(b) end
  end
  p = pth.abs(pth.resolve(p))
  if create or ix.exists(p) then
    return ed:focus(ed:buffer(p))
  end
  error'TODO: goto nav'
end

local DO_ENTRY = {
  focus  = nav.backFocus,
  back   = nav.doBack,
  expand = nav.doExpand,
}

--- perform the entry operation
nav.doEntry = function(ed, op, times, ls)
  local e = ed.edit; local l = e.l
  local fn = fmt.assertf(DO_ENTRY[op], 'uknown entry op: %s', op)
  e.l = fn(e.buf, l, times, ls) or l
end

M.path = function(ed, ev, evsend)
  log.trace('path: %q line=%i', ev, e.l)
  if ev.entry then
    nav.doEntry(ed, ev.entry, ev.times or 1, civix.dir)
  end
  if ev.go then nav.goPath(ed, 'create' == ev.go) end
end

--- Do something to the current buffer, depending on ev [+
--- * save=true: save the current buffer
--- ]
M.buf = function(ed, ev)
  if ev.save then ed.edit:save(ed) end
end

return M
