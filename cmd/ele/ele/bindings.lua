-- Bindings builin plugin
--
-- This defines the default keybindings and the function
-- for handling key inputs.
local M = mod and mod'ele.keys' or {}

local mty = require'metaty'
local fmt = require'fmt'
local ds = require'ds'
local et = require'ele.types'
local log = require'ds.log'

local sfmt = string.format
local push, pop, concat = table.insert, table.remove, table.concat
local getp, dp = ds.getp, ds.dotpath
local add = ds.add

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
  return fmt.assertf(et.term.literal(key),
    'invalid literal: %q', key)
end
M.chordstr = function(chord)
  local s = {}
  for _, key in ipairs(chord) do push(s, M.literal(key)) end
  return concat(s)
end

---------------------------
-- TYPES

--- The state of the keyboard input (chord).
--- Some bindings are a simple action to perform, whereas callable bindings
--- can update the KeySt to affect future ones, such as decimals causing
--- later actions to be repeated a [$num] of times.
M.KeySt = mty'KeySt' {
  "chord [table]: list of keys which led to this binding, i.e. {'space', 'a'}",
  "event [table]: table to use when returning (emitting) an event.",
  "next [table|string]: the binding which will be used for the next key",
  "keep [boolean]: if true the above fields will be preserved in next call",
}

--- Check the current Key State.
M.KeySt.check = function(k, ele) --> errstring?
  if k.next == nil then return end
  return (type(k.next) ~= 'table') and et.checkBinding(k.next)
    or getp(k, {'event', 'action'})
       and et.checkAction(ele, k.event.action)
end

--- A map of key -> binding.
--- The name and doc can be provided for the user.
--- 
--- Other "fields" must be valid chords. They will be automatically
--- split (by whitespace) to create sub-KeyBindings as-needed.
---
--- The value must be one of: [+
--- * KeyBindings instance to explicitly create chorded bindings.
--- * plain event table to fire off a simple event
--- * callable [$event(ev, keySt)] for more complex bindings.
--- ]
-- TODO: actually use this
M.KeyBindings = mty'KeyBindings' {
  'name [string]: the name of the group for documentation',
  'doc [string]: documentation to display to the user',
}
M.KeyBindings.getBinding = function(kb, k)
  return getmetatable(kb).__index(kb, k)
end
getmetatable(M.KeyBindings).__call = function(T, t)
  local b = {}
  for k, v in pairs(t) do T.__newindex(b, k, v) end
  return mty.constructUnchecked(T, b)
end
getmetatable(M.KeyBindings).__index = function(G, k)
  assert(et.term.checkKey(k))
end
M.KeyBindings.__newindex = function(kb, k, v)
  if M.KeyBindings.__fields[k] then
    assert(type(v) == 'string', k)
    rawset(kb, k, v)
    return
  end
  local mtv = getmetatable(v)
  fmt.assertf(mty.callable(v)
              or (mtv == M.KeyBindings)
              or (not mtv and type(v) == 'table'),
    '[%s] binding must be callable or plain table: %q', k, v)
  if k == 'fallback' then return rawset(kb,k, v) end
  k = M.chord(k); assert(#k > 0, 'empty chord')
  for i=1,#k-1 do
    local key = k[i]; assert(et.term.checkKey(key))
    if not rawget(kb,key) then
      rawset(kb,key, M.KeyBindings{
        name=table.concat(ds.slice(k, 1,i), ' '),
      })
    end
    kb = rawget(kb,key)
  end
  local key = k[#k]
  assert(et.term.checkKey(key))
  rawset(kb,key, v)
end

---------------------------
-- Default ed.bindings functions

M.exit = {action='exit'}

M.insertChord = function(keys)
  return ds.update(keys.event or {}, {
    M.chordstr(keys.chord), action='insert',
  })
end
M.unboundChord = function(keys)
  error('unbound chord: '..concat(keys.chord, ' '))
end

M.close       = {action='close'} -- close current focus
M.insertmode  = {mode='insert'}
M.insertsot   = {mode='insert', action='move', move='sot'}
M.inserteol   = {mode='insert', action='move', move='eol', cols=1}
M.commandmode = {mode='command'}

M.insertBelow = {
  action='chain', mode='insert',
  {action='move', move='eol', cols=1}, {action='insert', '\n'},
}
M.insertAbove = {
  action='chain', mode='insert',
  {action='move', move='sol'},         {action='insert', '\n'},
  {action='move', rows=-1},
}

M.moveAction = function(event)
  return function(keys)
    local ev = keys.event or {}
    ev.action = ev.action or 'move'
    return ds.update(ev, event)
  end
end
do local MA = M.moveAction
  M.right,   M.left      = MA{off=1},          MA{off=-1}
  M.forword, M.backword  = MA{move='forword'}, MA{move='backword'}
  M.up                   = MA{move='lines', lines=-1}
  M.down                 = MA{move='lines', lines=1}
  -- start/end of line/text
  M.sol, M.sot           = MA{move='sol'}, MA{move='sot'}
  M.eol, M.eot           = MA{move='eol'}, MA{move='eot'}
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

M.backspace = {action='remove', off=-1, cols1=-1}
M.delkey    = {action='remove', off=1}

--- delete until a movement command (or similar)
M.delete = function(keys)
  local ev = keys.event or {}; keys.event = ev
  if ev.action == 'remove' then
    ev.lines = 0
    return ev
  end
  ev.action = 'remove'
  keys.keep = true
end

M.change = function(keySt)
  local ev = M.delete(keySt)
  keySt.event.mode = 'insert'
  return ev
end
M.changeEol = function(keySt, evsend)
  M.delete(keySt)
  local ev = ds.pop(keySt, 'event')
  ev.move = 'eol'; ev.mode = 'insert'; ev.keep = false
  return ev
end

--- used for setting the number of times to do an action.
--- 1 0 d t x: delete till the 10th x
M.times = function(keys)
  local ev = keys.event or {}; keys.event = ev
  ev.times = (ev.times or 0) * 10 + tonumber(ds.last(keys.chord))
  keys.keep = true
end
M.zero = function(keys) -- special: movement if not after a digit
  local ev = keys.event or {}
  if not ev.action and ev.times then return M.times(keys) end
  ev.action, ev.move = ev.action or 'move', 'sol'
  return ev
end

---------------------------
-- KEYBOARD LAYOUT

-- Modes
M.insert  = M.KeyBindings{name='insert', doc='insert mode'}
M.command = M.KeyBindings{name='command', doc='command mode'}

-- Navigation
-- M.goPath      = {action='path', go=true}
-- M.createPath  = {action='path', go='create'}

-- Basic movement and times (used in multiple)
M.movement = {
  right = M.right, left=M.left, up=M.up, down=M.down,
  l     = M.right, h   =M.left, k =M.up, j   =M.down,
  w=M.forword, b=M.backword,
  t=M.till, T=M.tillback,
  ['^'] = M.sot, ['$'] = M.eol,

  -- times (note: 1-9 defined below)
  ['0'] = M.zero, -- sol+0times
}
-- times
for b=('1'):byte(), ('9'):byte() do
  M.movement[string.char(b)] = M.times
end

-----
-- INSERT
ds.update(M.insert, {
  fallback = M.insertChord,
  ['^q ^q'] = M.exit,
  esc       = M.commandmode,
  right = M.right, left=M.left, up=M.up, down=M.down,
  back = M.backspace, del=M.delkey,
})


-----
-- COMMAND
ds.update(M.command, M.movement)

ds.update(M.command, {
  fallback = M.unboundChord,
  ['^q ^q'] = M.exit,

  -- insert
  i = M.insertmode, I=M.insertsot, A=M.inserteol,
  o = M.insertBelow, O = M.insertAbove,

  d = M.delete,
  c = M.change, C = M.changeEol,

  -- movement
  f=M.find, F=M.findback,

  -- Navigation
  -- ['g f']           = M.goPath,
})

---------------------------
-- SYSTEM Mode

--- System mode
--- Mode for dealing with system-related resources such as
--- files, directories and running single line or block
--- commands directly in a buffer.
M.sys = M.KeyBindings {
  name = 'nav', doc = 'nav mode',
}
ds.update(M.sys, M.movement)

M.pathFocus  = {action='path', entry='focus'}
M.pathBack   = {action='path', entry='back'}
M.pathExpand = {action='path', entry='expand'}
M.pathFocusExpand = {action='chain', M.pathFocus, M.pathExpand}
M.pathBackExpand = {action='chain',
  M.pathFocus, M.pathBack, M.pathExpand,
}

ds.update(M.sys, {
  h = M.pathBack,   H = M.pathBackExpand,
  l = M.pathExpand, L = M.pathFocusExpand,

  -- TODO: J/K: focus below/above
})



---------------------------
-- INSTALL

-- install the builtin keys plugin
--
-- Note: this does NOT start the keyactions coroutine
M.install = function(ed)
  log.info('!! install %q', ed)
  ed.ext.keys = M.KeySt{}
  -- TODO: replace with merge but need shouldMerge closure.
  ed.modes = ds.update(ed.modes or {}, {
      insert=M.insert, command=M.command,
  })
  if not ed.namedBuffers.nav then
    ed.namedBuffers.nav = ed:buffer()
  end
end

-- keyactions coroutine.
-- This should be scheduled with LAP, see user.lua and testing.lua
M.keyactions = function(ed, keyrecv, evsend)
  assert(keyrecv:hasSender())
  log.info('keyactions keyrecv=%q', keyrecv)
  for key in keyrecv do
    log.info('key received: %q', key)
    if key == '^q' then
      ed.run = false; log.warn('received ^q, exiting')
    end
    if not ed.run then break end
    if key then
      if type(key) == 'string' then
        evsend{key, action='keyinput'}
        log.info('sent key %q', key)
      else assert(key[1] == 'size')
        local d = ed.display
        local ch = (d.h ~= key.h) or (d.w ~= key.w)
        d.h, d.w = key.h, key.w
        if ch then ed.redraw = true end
      end
    else ed.warn'received empty key' end
  end
  log.warn'exited keyactions'
end

return M
