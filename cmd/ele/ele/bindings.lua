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
-- TYPES

M.Keys = mty'Keys' {
  "chord [table]: list of keys which led to this binding, i.e. {'space', 'a'}",
  "event [table]: table to use when returning (emitting) an event.",
  "next [table|string]: the binding which will be used for the next key",
  "keep [boolean]: if true the above fields will be preserved in next call",
}

M.Keys.check = function(k, ele) --> errstring?
  return (type(k.next) ~= 'table') and et.checkBinding(k.next)
    or get(k, {'event', 'action'})
       and et.checkAction(ele, k.event.action)
end

---------------------------
-- Utility Functions and Callable Records

-- space-separated keys to a list, asserting valid keys
M.chord = function(str) --> keylist
  local checkKey = et.term.checkKey
  local keys = {}; for k in str:gmatch'%S+' do
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

M.moveAction = function(event)
  return function(keys)
    local ev = keys.event or {}
    ev.action = ev.action or 'move'
    return ds.update(ev, event)
  end
end

-- Return an updated keys.event when called (typically for an action)
M.Event = mty'Event'{}
getmetatable(M.Event).__call = mty.constructUnchecked
getmetatable(M.Event).__index = nil
M.Event.__newindex = nil
M.Event.__call = function(a, keys)
  keys.event = keys.event or {}
  return ds.update(keys.event, a)
end

-- Chain of literal events
M.Chain = mty'Chain'{}
M.Chain.__call = function(acts, keys)
  local ev = keys.event or {}; ev.action = 'chain'
  for i, act in ipairs(acts) do ev[i] = ds.copy(act) end
  return ev
end

-- Runs a given key chord (series of keys)
--   example: command.T = hotkey'd t' -- delete till 
M.Hotkey = mty'Hotkey' {}
getmetatable(M.Hotkey).__call = function(T, chord)
  return mty.construct(T, M.chord(chord))
end
M.Hotkey.__call = function(r, keys)
  local ev = keys.event or {}; ev.action = 'chain'
  for i, k in ipairs(r) do ev[i] = {action='hotkey', k} end
  return ev
end

---------------------------
-- Default ed.bindings functions

M.exit = M.Event{action='exit'}

M.insertChord = function(keys)
  return ds.update(keys.event or {}, {
    M.chordstr(keys.chord), action='insert',
  })
end
M.unboundChord = function(keys)
  error('unbound chord: '..concat(keys.chord, ' '))
end

M.insertmode  = M.Event{mode='insert'}
M.insertsol   = M.Event{mode='insert', action='move', move='sol'}
M.inserteol   = M.Event{mode='insert', action='move', move='eol'}
M.commandmode = M.Event{mode='command'}

do local MA = M.moveAction
  M.right,   M.left      = MA{off=1},          MA{off=-1}
  M.up,      M.down      = MA{lines=-1},       MA{lines=1}
  M.forword, M.backword  = MA{move='forword'}, MA{move='backword'}
end

M.movekey = function(keys)
  local ev = keys.event or {}
  ev[ev.move] = M.literal(ds.last(keys.chord))
  return ev
end

-- go to the character
M.find = function(keys)
  keys.event = keys.event or {}
  keys.event.action = keys.event.action or 'move'
  keys.event.move = 'find'
  keys.next = M.movekey
  keys.keep = true
end

-- go to the column before the character
M.till = function(keys)
  M.find(keys); keys.event.cols = -1
end

-- go back to the character
M.findback = function(keys)
  M.find(keys)
  keys.event.move = 'findback'
end

-- go back to the column after the character
M.tillback = function(keys)
  M.findback(keys); keys.event.cols = 1
end

M.backspace = M.Event{action='remove', off=-1, cols1=-1}
M.delkey    = M.Event{action='remove', off=1}

-- delete until a movement command (or similar)
M.delete = function(keys)
  local ev = keys.event or {}; keys.event = ev
  if ev.action == 'remove' then
    ev.lines = 0; return ev
  end
  ev.action = 'remove'
  keys.keep = true
end

M.change = function(keys)
  local ev = M.delete(keys); keys.event.mode = 'insert'
  return ev
end

-- used for setting the number of times to do an action.
-- 1 0 d t x: delete till the 10th x
M.times = function(keys)
  local ev = keys.event or {}; keys.event = ev
  ev.times = (ev.times or 0) * 10 + tonumber(ds.last(keys.chord))
  keys.keep = true
end
M.zero = function(keys) -- special: movement if not after a digit
  local ev = keys.event or {}
  if not ev.action and ev.times then return M.times(keys) end
  ev.action, ev.sol = ev.action or 'move', true
  return ev
end

---------------------------
-- KEYBOARD LAYOUT

-- bind chord to function
-- example: bind(B.insert, 'space a b', function(keys) ... end)
M.bind = function(b, chord, fn)
  assert(type(fn) == 'table' or mty.callable(fn),
    'can only bind to table or callable')
  chord = (type(chord) == 'string') and M.chord(chord) or chord
  assert(#chord > 0, 'chord is empty')
  local i, mpath = 1, {}
  while i < #chord do
    mpath[i] = mty.name(b)
    local key = chord[i]; if not rawget(b, key) then
      b[key] = mod and mod(concat(mpath)) or {}
    end
    b, i = b[key], i + 1
  end
  b[chord[i]] = fn
end
M.bindall = function(b, map)
  for chord, fn in pairs(map) do M.bind(b, chord, fn) end
end

-- Modes
M.insert  = mod and mod'ele.insert' or {}
M.command = mod and mod'ele.command' or {}


-----
-- INSERT
M.insert.fallback = M.insertChord
M.bindall(M.insert, {
  ['^q ^q'] = M.exit,
  esc       = M.commandmode,
  right = M.right, left=M.left, up=M.up, down=M.down,
  back = M.backspace, del=M.delkey,
})

-----
-- COMMAND
M.command.fallback = M.unboundChord
M.bindall(M.command, {
  ['^q ^q'] = M.exit,
  i = M.insertmode, I=M.insertsol, A=M.inserteol,

  -- movement
  right = M.right, left=M.left, up=M.up, down=M.down,
  l     = M.right, h   =M.left, k =M.up, j   =M.down,
  f=M.find, F=M.findback,
  t=M.till, T=M.tillback,

  -- times (note: 1-9 defined below)
  ['0'] = M.zero,

  d = M.delete, c = M.change,
})

-- delete/change
for b=('1'):byte(), ('9'):byte()
  do M.command[string.char(b)] = M.times end

---------------------------
-- INSTALL

-- install the builtin keys plugin
--
-- Note: this does NOT start the keyactions coroutine
M.install = function(ed)
  ed.ext.keys = M.Keys{}
  ed.modes = ds.merge(ed.modes or {}, {
      insert=M.insert, command=M.command,
  })
end

-- keyactions coroutine.
-- This should be scheduled with LAP, see user.lua and testing.lua
M.keyactions = function(ed, keyrecv, evsend)
  assert(keyrecv:hasSender())
  log.info('keyactions keyrecv=%q', keyrecv)
  for key in keyrecv do
    log.info('key received: %q', key)
    if key == '^q' then ed.run = false; log.warn('received ^q, exiting') end
    if not ed.run then break end
    if key then
      if type(key) == 'string' then
        evsend{key, action='keyinput'}
        log.info('sent key %q', key)
      else assert(key[1] == 'size')
        local d = ed.display; d.h, d.w = key.h, key.w
      end
    else ed.warn'received empty key' end
  end
  log.warn'exited keyactions'
end

return M
