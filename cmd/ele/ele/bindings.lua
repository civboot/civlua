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
local vt100 = require'vt100'

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
M.KeyBindings = mty'KeyBindings' {
  'name [string]: the name of the group for documentation',
  'doc [string]: documentation to display to the user',
}
M.KeyBindings.getBinding = rawget
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

M.splitVLeft  = {action='window', split='vertical'}
M.splitVRight = {action='window', split='vertical',   moveH=1}
M.splitHUp    = {action='window', split='horizontal'}
M.splitHDown  = {action='window', split='horizontal', moveV=1}

M.windowUp    = {action='window', moveV=-1}
M.windowDown  = {action='window', moveV=1}
M.windowLeft  = {action='window', moveH=-1}
M.windowRight = {action='window', moveH=1}

M.close  = {action='window', close=true}

M.insertChord = function(keys)
  return ds.update(keys.event or {}, {
    M.chordstr(keys.chord), action='insert',
  })
end
M.unboundChord = function(keys)
  error('unbound chord: '..concat(keys.chord, ' '))
end

M.commandMode = {mode='command'}
M.insertMode  = {mode='insert'}
M.systemMode  = {mode='system'}

M.insertTab   = {action='insertTab'}
M.insertsot   = {mode='insert', action='move', move='sot'}
M.inserteol   = {mode='insert', action='move', move='eol', cols=1}

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
  M.sof, M.eof           = MA{move='sof'}, MA{move='eof'}
  M.upScreen             = MA{move='screen', mul=-1, div=2}
  M.downScreen           = MA{move='screen', mul=1,  div=2}
end

M.moveG = function(keySt) -- specific line or end-of-file
  local ev = keySt.event or {}
  return ev.times and {action='move', move='absolute', l=ev.times} or M.eof
end

M.movekey = function(keys)
  local ev = keys.event or {}
  ev[ev.move] = M.literal(ds.last(keys.chord))
  return ev
end

-- Find a single character.
M.find = function(keys)
  local ev = keys.event or {}; keys.event = ev
  ev.action, ev.move = ev.action or 'move', ev.move or 'find'
  keys.next = M.movekey
  keys.keep = true
end

--- go to the column before the character
M.till = function(keys)
  M.find(keys); keys.event.cols = -1
end

--- go back to the character
M.findback = function(keys)
  M.find(keys)
  keys.event.move = 'findback'
end

--- go back to the column after the character
M.tillback = function(keys)
  M.findback(keys); keys.event.cols = 1
end

M.backspace = {action='remove', off=-1, cols1=-1}
M.delkey    = {action='remove', off=1}

--- delete until a movement command (or similar)
M.delete = function(keySt)
  local ev = keySt.event or {}; keySt.event = ev
  if ev.action == 'remove' then
    ev.lines = 0
    return ev
  end
  ev.action = 'remove'
  keySt.keep = true
end
M.deleteEol = function(keySt)
  M.delete(keySt)
  local ev = ds.popk(keySt, 'event')
  ev.move, keySt.keep = 'eol', nil
  return ev
end

--- Delete <move> then enter insert.
M.change = function(keySt)
  local ev = M.delete(keySt)
  keySt.event.mode = 'insert'
  return ev
end
M.changeEol = function(keySt, evsend)
  M.delete(keySt)
  local ev = ds.popk(keySt, 'event')
  ev.move, ev.mode, keySt.keep = 'eol', 'insert', nil
  log.info('!! changeEol returns', ev)
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
-- Search Buffer

M.hideOverlay = {action='buf', buf='b#overlay', ext={show=false}}

M.searchBufNext = {action='searchBuf', next=true}
M.searchBufPrev = {action='searchBuf', prev=true}
M.searchBufSub  = {action='searchBuf', next=true, sub=true, wrap=true}

--- Interactively search the buffer.
---
--- This holds onto keySt (sets .keep), effectively owning all keyboard
--- inputs.
M.searchBuf = function(keySt)
  local ev, chord = keySt.event or {}, keySt.chord
  keySt.event, keySt.keep = ev, true
  if #chord == 1 then -- initial call
    keySt.next = M.searchBuf
    return {action='buf', buf='b#overlay', clear=true, ext={show=true}}
  end
  local k, bufAction = chord[#chord], nil

  -- TODO: do tab / ^j / ^k / etc
  if k == 'back' then
    bufAction = {action='buf', buf='b#overlay', remove={1,-1,1,-1}}
  end
  if k == '^n' then return ds.update({overlay=true}, M.searchBufSub) end
  if k == 'enter' then
    keySt.keep = false
    return {action='chain',
      M.hideOverlay, ds.update({overlay='store'}, M.searchBufNext)
    }
  end

  local char = vt100.literal(k); if char then
    bufAction = {action='buf', buf='b#overlay', insert={char, 1,'end'}}
  end
  if bufAction then return {action='chain',
    bufAction,
    {action='searchBuf', overlay=true}
  } end
  keySt.keep = false -- any unknown control exits find w/out save
  return M.hideOverlay
end


---------------------------
-- SYSTEM Mode
M.goPath      = {action='path', go='path',   mode='command'}
M.createPath  = {action='path', go='create', mode='command'}

M.pathFocus  = {action='path', entry='focus'}
M.pathBack   = {action='path', entry='back'}
M.pathExpand = {action='path', entry='expand'}
M.pathFocusExpand = {action='chain', M.pathFocus, M.pathExpand}
M.pathBackExpand = {action='chain',
  M.pathFocus, M.pathBack, M.pathExpand,
}

M.save = {action='edit', save=true}
M.undo = {action='edit', undo=true}
M.redo = {action='edit', redo=true}

--- CWD: current working directory
M.navCwd = {action='nav', nav='cwd', mode='system'}

--- CBD: current buffer id
M.navCbd = {action='nav', nav='cbd', mode='system'}

--- View list of buffers
M.navBuf = {action='nav', nav='buf', mode='system'}

---------------------------
-- INSTALL

-- install the builtin keys plugin
--
-- Note: this does NOT start the keyactions coroutine
M.install = function(ed)
  ed.ext.keys = M.KeySt{}
  -- TODO: replace with merge but need shouldMerge closure.
  ed.modes = ds.update(ed.modes or {}, {
      insert=M.insert, command=M.command, system=M.system,
  })
  if not ed.namedBuffers.nav then
    push(ed:namedBuffer'nav'.tmp, ed.ext.keys) -- mark as not closed
  end
  if not ed.namedBuffers.find then
    push(ed:namedBuffer'find'.tmp, ed.ext.keys) -- mark as not closed
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
      evsend{action='exit'}
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

---------------------------
-- BINDINGS

--- Basic movement and times (used in multiple)
M.movement = {
  h   =M.left, j   =M.down, k =M.up, l     = M.right,
  left=M.left, down=M.down, up=M.up, right = M.right,

  w=M.forword,   b=M.backword,
  t=M.till,      T=M.tillback,
  ['^'] = M.sot, ['$'] = M.eol,

  -- times (note: 1-9 defined below)
  ['0'] = M.zero, -- sol+0times
}

-- times
for b=('1'):byte(), ('9'):byte() do
  M.movement[string.char(b)] = M.times
end


M.searchBindings = {
  ['/'] = M.searchBuf,
  n = M.searchBufNext, N = M.searchBufPrev, ['^n'] = M.searchBufSub,
}

--- Insert Mode: directly insert text into the buffer.
M.insert  = M.KeyBindings{name='insert', doc='insert mode'}
ds.update(M.insert, {
  fallback = M.insertChord,
  ['^q']   = M.exit,
  esc      = M.commandMode,
  tab      = M.insertTab,
  right = M.right, left=M.left, up=M.up, down=M.down,
  back=M.backspace, del=M.delkey,
})

--- Command Mode: control the editor's text functions and
--- enter other modes.
M.command = M.KeyBindings{name='command', doc='command mode'}
ds.update(M.command, M.movement)
ds.update(M.command, M.searchBindings)
ds.update(M.command, {
  fallback = M.unboundChord,
  ['^q ^q'] = M.exit,

  -- insert
  i = M.insertMode, I=M.insertsot, A=M.inserteol,
  o = M.insertBelow, O = M.insertAbove,

  d = M.delete, D = M.deleteEol,
  c = M.change, C = M.changeEol,

  -- movement
  f=M.find, F=M.findback,
  ['^d'] = M.downScreen, ['^u'] = M.upScreen,

  -- Search
  ['/'] = M.searchBuf,
  n = M.searchBufNext, N = M.searchBufPrev, ['^n'] = M.searchBufSub,

  -- System
  s = M.systemMode,

  -- G is for GO
  ['g g'] = M.sof,    ['G'] = M.moveG, -- start/end of file

  ['g f'] = M.goPath, ['g F'] = M.createPath,
  ['g /'] = M.navCwd, ['g .'] = M.navCbd, ['g b'] = M.navBuf,

  -- Window
  ['g h'] = M.windowLeft, ['g l'] = M.windowRight,
  ['g j'] = M.windowDown, ['g k'] = M.windowUp,

  ['g H'] = M.splitVLeft, ['g L'] = M.splitVRight,
  ['g J'] = M.splitHDown, ['g K'] = M.splitHUp,

  -- Other
  u = M.undo, ['^r'] = M.redo,
})

--- System mode: view and control system-related resources such as
--- files and directories. Run single line or block commands (lua,
--- shell) directly in a buffer.
M.system = M.KeyBindings {
  name = 'system',
  doc = 'system mode: filesystem, commands, shell, etc',
}
ds.update(M.system, M.movement)
ds.update(M.system, M.searchBindings)
ds.update(M.system, {
  fallback = M.unboundChord,
  esc      = M.commandMode,
  enter    = {action='path', enter=true},

  s = M.save,
  g = M.goPath,

  h = M.pathBack,   H = M.pathBackExpand,
  l = M.pathExpand, L = M.pathFocusExpand,
  -- TODO: J/K: focus below/above

  -- Other
  u = M.undo, ['^r'] = M.redo,
})

return M