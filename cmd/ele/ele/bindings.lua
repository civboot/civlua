-- Bindings builin plugin
--
-- This defines the default keybindings and the function
-- for handling key inputs.
local M = mod and mod'ele.keys' or {}

local mty = require'metaty'
local ds = require'ds'
local et = require'ele.types'
local log = require'ds.log'

local sfmt = string.format
local push, pop, concat = table.insert, table.remove, table.concat
local get, set, dp = ds.get, ds.set, ds.dotpath
local add = ds.add

---------------------------
-- Utility Functions

-- space-separated keypath to a list, asserting valid keys
M.keypath = function(keystr) --> keylist
  local checkKey = et.term.checkKey
  local keys = {}; for k in keystr:gmatch'%S+' do
    push(keys, assert(checkKey(k)))
  end
  return keys
end

M.literal = function(key)
  return mty.assertf(et.term.literal(key),
    'invalid literal: %q', key)
end
M.chordstr = function(chord)
  local s = {}
  for _, key in ipairs(chord) do push(s, M.literal(key)) end
  return concat(s)
end

-- create a binding that emits the action event
local function act(action, event)
  event.action = action
  return function(keys) return ds.update(keys.event, event) end
end
local function move(event)
  return function(keys)
    local ev = keys.event
    ev.action = ev.action or 'move'
    return ds.update(ev, event)
  end
end

---------------------------
-- Type for data.keys

M.Keys = mty'Keys' {
  "mode [string]: mode from bindings.modes",
  "chord [table]: list of keys which led to this binding, i.e. {'space', 'a'}",
  "event [table]: table to use when returning (emitting) an event.",
  "next [table|string]: the binding which will be used for the next key",
  "keep [boolean]: if true the above fields will be preserved in next call",
}

M.Keys.check = function(k, ele) --> errstring?
  return et.checkMode(ele, k.mode)
    or (type(k.next) ~= 'table') and et.checkBinding(ele, k.next)
    or k.event.action and et.checkAction(ele, k.event.action)
end

---------------------------
-- Default data.bindings functions

M.bindings = {}
local B = M.bindings

B.insertChord = function(keys)
  return ds.update(keys.event, {
    M.chordstr(keys.chord), action='insert',
  })
end
B.unboundChord = function(keys)
  error('unbound chord: '..concat(keys.chord, ' '))
end

B.insertmode  = function(keys) keys.mode = 'insert'  end
B.commandmode = function(keys) keys.mode = 'command' end

B.right, B.left = move{off=1},    move{off=-1}
B.up,    B.down = move{lines=-1}, move{lines=1}

B.forword  = act('move', {move='forword'})
B.backword = act('move', {move='backword'})

B.movekey = function(keys)
  local ev = keys.event
  ev[ev.move] = M.literal(ds.last(keys.chord))
  return ev
end

-- go to the character
B.find = function(keys)
  ds.setIfNil(keys.event, 'action', 'move')
  keys.event.move = 'find'
  keys.next = 'movekey'
  keys.keep = true
end

-- go to the column before the character
B.till = function(keys)
  B.find(keys); keys.event.cols = -1
end

-- go back to the character
B.findback = function(keys)
  B.find(keys)
  keys.event.move = 'findback'
end

-- go back to the column after the character
B.tillback = function(keys)
  B.findback(keys); keys.event.cols = 1
end

B.backspace = act('remove', {off=-1})
B.delkey    = act('remove', {off=1})

-- delete until a movement command (or similar)
B.delete = function(keys)
  local ev = keys.event
  if ev.action == 'remove' then
    ev.lines = 0; return ev
  end
  ev.action = 'remove'
  keys.keep = true
end

B.change = function(keys)
  keys.event.mode = 'insert' -- action sets mode
  return B.delete(keys)
end

-- used for setting the number of times to do an action.
-- 1 0 d t x: delete till the 10th x
B.times = function(keys)
  local ev = keys.event
  ev.times = (ev.times or 0) * 10 + tonumber(ds.last(keys.chord))
  keys.keep = true
end
B.zero = function(keys) -- special: movement if not after a digit
  local ev = keys.event
  if not ev.action and ev.times then return B.times(keys) end
  ev.action, ev.sol = ev.action or 'move', true
  return ev
end

---------------------------
-- Default Layout

B.modes = {}
B.modes.insert, B.modes.command = {}, {}; do
  local char = string.char
  local I, C = B.modes.insert, B.modes.command
  -----
  -- INSERT
  I.fallback = 'insertChord'
  I.esc      = 'commandmode'
  I.right, I.left, I.up, I.down = 'right', 'left', 'up', 'down'
  I.back, I.del = 'backspace', 'delkey'

  -----
  -- COMMAND
  C.fallback = 'unboundChord'
  C.esc      = 'commandmode'
  C.i        = 'insertmode'

  -- movement
  C.right, C.left, C.up, C.down = 'right', 'left', 'up', 'down'
  C.l,     C.h,    C.j,  C.k    = 'right', 'left', 'up', 'down'
  C.f, C.t, C.F, C.T = 'find', 'till', 'findback', 'tillback'

  -- times
  C['0'] = 'zero'
  for b=('1'):byte(), ('9'):byte() do C[char(b)] = 'times' end

  -- delete/change
  C.d = 'delete'
  C.c = 'change'
end

---------------------------
-- Action and installation

M.action = function(data, ev, evsend)
  local ki = assert(ev[1])
  local K, B = data.keys, data.bindings
  log.info('action: %q mode=%s keep=%s', ev, K.mode, K.keep)
  if K.keep then K.keep = nil
  else
    K.chord, K.event = {}, {}
    K.next = B.modes[K.mode]
  end
  local n = type(K.next) == 'string' and K.next
    or K.next[ki] or B.modes[K.mode].fallback
  if type(n) == 'table' then
    K.next, K.keep = n, true
    return
  end
  push(K.chord, ki)
  log.info(' + binding=%q chord=%q', n, K.chord)
  local ev = (B[n] or error(sfmt('no binding: %s', n)))(K)
  if ev then
    evsend(ev); K.mode = ev.mode or K.mode
  end
  local err = K:check(data); if err then
    keys.keep = false
    if et.checkMode(data, K.mode) then K.mode = 'insert' end
    error(sfmt('bindings.%s(keys) -> invalid keys: %s', n, err))
  end
end

-- install the builtin keys plugin
--
-- Note: this does NOT start the keyinputs coroutine
M.install = function(data)
  data.keys = M.Keys{mode='insert'}
  data.bindings = data.bindings or {}
  ds.deepUpdate(data.bindings, M.bindings)
end

return M
