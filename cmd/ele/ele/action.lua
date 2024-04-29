local pkg = require'pkg'
local mty = pkg'metaty'
local ds = pkg'ds'
local gap = pkg'rebuf.gap'
local T = pkg'ele.types'
local keys = pkg'ele.keys'
local motion = pkg'rebuf.motion'
local window = pkg'ele.window'

local Action = T.Action
local ty = mty.ty
local min, max, bound, sort2 = ds.min, ds.max, ds.bound, ds.sort2

local add = table.insert

local M = {}
M.ActStep = 0

M.Actions = {}
getmetatable(Action).__call = function(T, act)
  local name = assert(act.name)
  if not act.override and M.Actions[name] then
    error('Action already defined: ' .. name)
  end
  M.Actions[name] = mty.construct(T, act)
  return M.Actions[name]
end

-- Helpful for constructing "state chains"
-- State chains simply build up an event by adding
-- data and modifying the name to execute a different
-- action.
--
-- If name='chain' then the mdl will store it
-- and include it in the next rawKey event.
local function chain(ev, name, add)
  ev.chain = ev.chain or {}; table.insert(ev.chain, ev[1])
  ev.depth = nil
  ev[1] = name; if add then ds.update(ev, add) end
  return {ev}, true
end

local function execChain(mdl, ev)
  local evs, sless = M.Actions[ev.exec].fn(mdl, ev)
  assert(not evs)
  return evs, sless
end

local function doTimes(ev, fn)
  for _=1, ev.times or 1 do fn() end
end

M.move = function(mdl, ev)
  local e = mdl.edit; e.l, e.c = ev.l, ev.c
end
local function clearState(mdl)
  mdl.chain = nil
end
M.insert = function(mdl)
  mdl.mode = 'insert'; clearState(mdl)
end
M.deleteEoL = function(mdl)
  local e = mdl.edit; e:remove(e.l, e.c, e.l, #e:curLine())
end

---------------------------------
-- Core Functionality
Action{ name='chain', brief='start/continue a chain', fn = function(mdl, ev)
  mdl.chain = ev
end}
Action{ name='move', brief='move cursor', fn = M.move, }

---------------------------------
-- Insert Mode
Action{ name='insert', brief='go to insert mode',
  fn = function(mdl)
    mdl.edit:changeStart(); M.insert(mdl)
  end,
}

local function handleAction(mdl, action, ev, chordAction)
  if not action then
    return chain(ev, 'unboundKey')
  elseif Action == ty(action) then -- found, continue
    return chain(ev, action.name)
  elseif M.Actions[action[1]] then
    return {action} -- raw event
  elseif 'table' == ty(action) then
    return chain(ev, chordAction)
  end error(mty.fmt(action))
end

Action{
  name='rawKey', brief='the raw key handler (directly handles all key events)',
  fn = function(mdl, ev)
    local key = assert(ev.key)
    assert(type(key) == 'string', key)
    if ev.execRawKey then
      return chain(ev, ds.steal(ev, 'execRawKey'), {rawKey=true})
    end
    local action = mdl:getBinding(key)
    ev.key = key
    return handleAction(mdl, action, ev, 'chord')
  end,
}
Action{
  name='chord', brief='start a keyboard chord',
  fn = function(mdl, ev)
    return chain(ev, 'chain', {execRawKey='chordChar', chord={ev.key}})
  end,
}
Action{
  name='chordChar', brief='start a keyboard chord',
  fn = function(mdl, ev)
    add(ev.chord, ev.key)
    ev.execRawKey='chordChar'
    local action = mdl:getBinding(ev.chord)
    return handleAction(mdl, action, ev, 'chain')
  end,
}

local function unboundCommand(mdl, keys)
  mdl:unrecognized(keys); return nil, true
end
local function unboundInsert(mdl, ks)
  if not mdl.edit then return mdl:status(
    'open a buffer to insert', 'info'
  )end
  for _, k in ipairs(ks) do
    if not keys.insertKey(k) then
      mdl:unrecognized(k); return nil, true
    else
      mdl.edit:insert(keys.KEY_INSERT[k] or k)
    end
  end
end

Action{
  name='unboundKey', brief='handle unbound key',
  fn = function(mdl, event)
    local key = assert(event.key)
    if mdl.mode == 'command' then
      return unboundCommand(mdl, {key})
    elseif mdl.mode == 'insert' then
      return unboundInsert(mdl, {key})
    end
  end,
}
Action{
  name='back', brief='delete previous character',
  fn = function(mdl, ev)
    return doTimes(ev, function()
      local l, c = mdl.edit:offset(-1)
      mdl.edit:removeOff(-1, l, c)
    end)
  end,
}

M.wantSpaces = function(col, spaces) return spaces - (col - 1) % spaces end
local function tabN(mdl, spaces)
  local e = mdl.edit; return function()
    for _=1, M.wantSpaces(e.c, spaces) do e:insert(' ') end
  end
end

Action{
  name='tab2', brief='tab inserts 2 spaces',
  fn = function(mdl, ev) return doTimes(ev, tabN(mdl, 2)) end,
}
Action{
  name='tab3', brief='tab inserts 3 spaces',
  fn = function(mdl, ev) return doTimes(ev, tabN(mdl, 3)) end,
}
Action{
  name='tab4', brief='tab inserts 4 spaces',
  fn = function(mdl, ev) return doTimes(ev, tabN(mdl, 4)) end,
}

---------------------------------
-- Command Mode
Action{ name='command', brief='go to command mode',
  fn = function(mdl)
    if mdl.mode == 'insert' then mdl.edit:changeUpdate2() end
    mdl.mode = 'command'; clearState(mdl)
  end,
}
Action{ name='quit', brief='quit the application',
  fn = function(mdl) mdl.mode = 'quit'    end,
}

-- Direct Modification
Action{ name='appendLine', brief='append to line', fn = function(mdl)
  mdl.edit:changeStart()
  mdl.edit.c = mdl.edit:colEnd(); M.insert(mdl)
end}
Action{ name='changeEoL', brief='change to EoL', fn = function(mdl)
  mdl.edit:changeStart()
  M.deleteEoL(mdl); M.insert(mdl)
end}
Action{ name='deleteEoL', brief='delete to EoL',
  fn = function(mdl)
    mdl.edit:changeStart(); M.deleteEoL(mdl)
  end,
}
Action{ name='insertLine',
  brief='add a new line and go to insert mode',
  fn = function(mdl, ev)
    local e = mdl.edit; e:changeStart();
    local c = e.c; e.c = e:colEnd()
    doTimes(ev, function() e:insert('\n') end)
    M.insert(mdl)
  end,
}
Action{ name='insertLineAbove',
  brief='add a new line above and go to insert mode',
  fn = function(mdl, ev)
    local e = mdl.edit; e:changeStart();
    e.l = bound(e.l - 1, 1, e:len()); e.c = e:colEnd()
    doTimes(ev, function() e:insert('\n') end)
    M.insert(mdl)
  end,
}
local bol = Action{ name='BoL', brief='goto beginning of line',
  fn = function(mdl, ev)
    local e = mdl.edit
    e.c = e:curLine():find('%S') or #e:curLine()
  end
}
Action{ name='changeBoL', brief='change at beginning of line',
  fn = function(mdl, ev)
    mdl.edit:changeStart(); bol.fn(mdl, ev); M.insert(mdl)
  end
}
Action{ name='del1', brief='delete single character',
  fn = function(mdl, ev) doTimes(ev, function()
      mdl.edit:changeStart(); mdl.edit:removeOff(1)
    end)
  end
}
Action{ name='splitVertical', brief='Split the screen verticly',
  fn = function(mdl, ev) window.splitEdit(mdl.edit, 'v') end
}
Action{ name='splitHorizontal', brief='Split the screen horizontally',
  fn = function(mdl, ev) window.splitEdit(mdl.edit, 'h') end
}
Action{ name='focusLeft', brief='Move focus to the left window',
  fn = function(mdl, ev) mdl:moveFocus('left') end
}
Action{ name='focusRight', brief='Move focus to the right window',
  fn = function(mdl, ev) mdl:moveFocus('right') end
}
Action{ name='focusUp', brief='Move focus to the up window',
  fn = function(mdl, ev) mdl:moveFocus('up') end
}
Action{ name='focusDown', brief='Move focus to the down window',
  fn = function(mdl, ev) mdl:moveFocus('down') end
}
Action{ name='editClose', brief='Close the current edit view',
  fn = function(mdl, ev)
    local e = window.viewClosestSibling(mdl.edit)
    window.viewRemove(mdl.edit)
    mdl.edit:close()
    if e then
      mdl.edit = e
    else
      mdl.edit = mdl.statusEdit
      mdl.view = mdl.statusEdit
    end
  end
}

----------------
-- Movement: these can be used by commands that expect a movement
--           event to be emitted.

-- Do movement function.
-- If this ever results in a stateless movement
-- or action then short-circuit and return
-- whether state happened.
local function doMovement(mdl, ev, fn, once)
  local e, sless = mdl.edit, true
  for _=1, ev.times or 1 do
    local l, c = fn(mdl, ev)
    if not l or not c then break end
    l, c = bound(l, 1, mdl.edit:len()), max(1, c)
    if ev.exec then
      ev.l, ev.c = l, c
      sless = select(2, execChain(mdl, ev))
    else
      e.l, e.c, sless = l, c, false
    end
    if sless or once then break end
  end
  return nil, sless
end

Action{ name='left', brief='move cursor left',
  fn = function(mdl, ev) return doMovement(mdl, ev,
    function(mdl, ev)
      return mdl.edit.l, max(1, mdl.edit.c - 1)
    end
  )end,
}
Action{ name='up', brief='move cursor up',
  fn = function(mdl, ev) return doMovement(mdl, ev,
    function(mdl, ev)
      return max(1, mdl.edit.l - 1), mdl.edit.c
    end
  )end,
}
Action{ name='right', brief='move cursor right',
  fn = function(mdl, ev) return doMovement(mdl, ev,
    function(mdl, ev)
      local c = min(mdl.edit.c + 1, #mdl.edit:curLine() + 1)
      return mdl.edit.l, c
    end
  )end,
}
Action{ name='down', brief='move cursor down',
  fn = function(mdl, ev) return doMovement(mdl, ev,
    function(mdl, ev)
      local e = mdl.edit
      return bound(e.l + 1, 1, e:len()), e.c
    end
  )end,
}
Action{ name='forword', brief='find the start of the next word',
  fn = function(mdl, ev) return doMovement(mdl, ev,
    function(mdl, ev)
      local e = mdl.edit; local l, c, len = e.l, e.c, e:len()
      while l <= len do
        c = motion.forword(e.buf.gap:get(l), c)
        if c then return l, c end
        l = l + 1; if l > len then break end
        c = 1
      end
      return len, #e:lastLine() + 1
    end
  )end,
}
Action{ name='backword', brief='find the start of this (or previous) word',
  fn = function(mdl, ev) return doMovement(mdl, ev,
    function(mdl, ev)
      local e = mdl.edit; local l, c = e.l, e.c
      while l > 0 do
        c = motion.backword(e.buf.gap:get(l), c)
        if c then return l, c end
        l = l - 1; if l <= 0 then break end
        c = #e.buf.gap:get(l) + 1
      end
      return 1, 1
    end
  )end,
}
Action{ name='SoL', brief='start of line',
  fn = function(mdl, ev) return doMovement(mdl, ev,
    function(mdl, ev)
      return mdl.edit.l, 1
    end
  )end,
}
Action{ name='EoL', brief='end of line',
  fn = function(mdl, ev) return doMovement(mdl, ev,
    function(mdl, ev)
      return mdl.edit.l, mdl.edit:colEnd()
    end
  )end,
}
Action{ name='goTo', brief='go to top of buf',
  fn = function(mdl, ev)
    doMovement(mdl, ev,
      function(mdl, ev) return ev.times or 1, 1 end
  , true)end,
}
Action{ name='goBot', brief='go to bottom of buf',
  fn = function(mdl, ev) doMovement(mdl, ev,
    function(mdl, ev)
      local e = mdl.edit
      return e:len(), #e:lastLine() + 1
    end
  )end,
}

----------------
-- Chains
Action{ name='times',
  brief='do an action multiple times (set with 1-9)',
  fn = function(mdl, ev)
    if '0' == ev.key and not ev.times then
      return chain(ev, 'SoL')
    end
    return chain(ev, 'chain', {
      times=((ev.times or 0) * 10) + tonumber(ev.key)
    })
  end
}

----
-- Replace Character
Action{ name='replace1', brief='replace character',
  fn = function(mdl, ev)
    return chain(ev, 'chain', {execRawKey='replaceChar'})
  end
}
Action{ name='replaceChar', brief='(called by replace1)',
  fn = function(mdl, ev)
    mdl.edit:changeStart();
    local ch, e = ev.key, mdl.edit; assert(ev.rawKey)
    if #ch ~= 1 then
      mdl:status('replace='..ch, 'invalid')
      return
    end
    e:replace(ev.key, e.l, e.c, e.l, e.c)
  end,
}
----
-- Find Character
Action{ name='find', brief='find next character',
  fn = function(mdl, ev)
    return chain(ev, 'chain', {execRawKey='findChar'})
  end
}
Action{ name='findChar', brief='find a specific character',
  fn = function(mdl, ev) return doMovement(mdl, ev,
    function(mdl, ev)
      local ch, e = ev.key, mdl.edit; assert(ev.rawKey)
      if #ch ~= 1 then
        mdl:status('find='..ch, 'invalid')
        return
      end
      return mdl.edit.l, e:curLine():find(ch, e.c)
    end
  )end,
}
Action{ name='findBack', brief='find prev character',
  fn = function(mdl, ev)
    return chain(ev, 'chain', {execRawKey='findCharBack'})
  end
}
Action{ name='findCharBack', brief='find a specific character',
  fn = function(mdl, ev) return doMovement(mdl, ev,
    function(mdl, ev)
      local ch, e = ev.key, mdl.edit; assert(ev.rawKey)
      if #ch ~= 1 then
        mdl:status('find='..ch, 'invalid')
        return
      end
      local r = e:curLine():sub(1, e.c-1):reverse()
      local i = r:find(ch)
      return mdl.edit.l, i and (#r - i + 1)
    end
  )end,
}

----
-- Delete
Action{ name='delete', brief='delete to movement',
  fn = function(mdl, ev)
    mdl.edit:changeStart();
    if ev.exec == 'deleteDone' and ev.key == 'd' then
      return chain(ev, 'deleteLine')
    end
    return chain(ev, 'chain', {exec='deleteDone'})
  end
}
Action{ name='deleteLine', brief='delete line',
  fn = function(mdl, ev)
    return doTimes(ev, function()
      local e = mdl.edit
      e:remove(e.l, e.l)
      e.l = min(1, e.l - 1)
    end)
  end,
}
local function _deleteDone(mdl, ev)
  local e = mdl.edit, assert(ev.l and ev.c)
  local c, c2
  if e.l == ev.l then
    c, c2 = sort2(e.c, ev.c)
    e:remove(e.l, c, ev.l, c2 - 1)
    if ev.c < e.c then e.c = ev.c end
  else e:remove(e.l, ev.l)
  end
end
Action{ name='deleteDone', brief='delete to movement (done)',
  fn = function(mdl, ev) _deleteDone(mdl, ev) end
}

----
-- Change
Action{ name='change', brief='change to movement',
  fn = function(mdl, ev)
    mdl.edit:changeStart();
    if ev.exec == 'changeDone' and ev.key == 'c' then
      return chain(ev, 'changeDone')
    end
    return chain(ev, 'chain', {exec='changeDone'})
  end
}
Action{ name='changeLine', brief='change line',
  fn = function(mdl, ev)
    return doTimes(ev, function()
      local e = mdl.edit
      e:remove(e.l, e.l)
      e.l = min(1, e.l - 1)
      M.insert(mdl)
    end)
  end,
}
Action{ name='changeDone', brief='change to movement (done)',
  fn = function(mdl, ev)
    _deleteDone(mdl, ev)
    M.insert(mdl)
  end
}

----
-- Search
Action{ name='search', brief='search for pattern',
  fn = function(mdl, ev)
    local e = mdl.searchEdit
    if not ev.search then
      mdl:showSearch()
      e:changeStart();
      e:trailWs()
      return chain(ev, 'chain', {execRawKey='search', search=''})
    end
    local k = keys.insertKey(ev.key)
    local search = ev.search .. (k or ('<'..ev.key..'>'))
    if ev.key == '^N' then return chain(ev, 'searchPrev')
    elseif k == '\n'  then return chain(ev, 'searchNext')
    elseif not k then
      mdl:status('search='..search, 'stop'); window.viewRemove(e)
    else -- append to search, keep searching
      assert(#k == 1)
      e:remove(e:len(), e:len())
      e:append(search)
      return chain(ev, 'chain', {execRawKey='search', search=search})
    end
  end
}

local function searchKind(gapSearch, inc)
  return function(mdl, ev)
    local out = doMovement(mdl, ev, function(mdl, ev)
      local e, search = mdl.edit, mdl.searchEdit:lastLine()
      local l, c = e.buf.gap[gapSearch](e.buf.gap, search, e.l, e.c + inc)
      if l and c then return l, c
      else mdl:status(string.format('not found: %q', search), 'find')
      end
    end)
    window.viewRemove(mdl.searchEdit)
    return out
  end
end
Action{ name='searchNext', brief='search for pattern',
  fn = searchKind('find', 1),
}
Action{ name='searchPrev', brief='search for previous pattern',
  fn = searchKind('findBack', -1),
}

----
-- Undo / Redo
Action{ name='undo', brief='undo previous action',
  fn = function(mdl, ev)
    mdl.edit:undo()
  end,
}
Action{ name='redo', brief='redo previous undo',
  fn = function(mdl, ev)
    mdl.edit:redo()
  end,
}


return M
