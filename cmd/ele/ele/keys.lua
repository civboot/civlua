-- Keys builin plugin
local M = mod and mod'keys' or {}

local mty = require'metaty'
local ds = require'ds'
local et = require'ele.types'
local log = require'ds.log'

local sfmt = string.format
local push, pop, concat = table.insert, table.remove, table.concat
local get, set, dp = ds.get, ds.set, ds.dotpath
local add = ds.add

-- space-separated keypath to a list, asserting valid keys
M.keypath = function(keystr) --> keylist
  local checkKey = et.term.checkKey
  local keys = {}; for k in keystr:gmatch'%S+' do
    push(keys, assert(checkKey(k)))
  end
  return keys
end

---------------------------
-- Keys type

M.Keys = mty'Keys' {
  "mode [string]: mode from bindings.modes",
  "chord [table]: list of keys which led to this binding, i.e. {'space', 'a'}",
  "event [table]: table to use when returning (emitting) an event.",
  "next [table|string]: the binding which will be used for the next key",
  "keep [boolean]: if true the above fields will be preserved for next call",
}

M.Keys.check = function(k, ele) --> errstring?
  return et.checkMode(ele, k.mode)
    or (type(k.next) ~= 'table') and et.checkBinding(ele, k.next)
    or k.event.action and et.checkAction(ele, k.event.action)
end

---------------------------
-- Bindings
M.bindings = {}
local B = M.bindings

B.insertChord = function(keys)
  return ds.update(keys.event, {
    action='insertChord',
    chord=keys.chord,
  })
end

B.unboundChord = function(keys)
  log.err('unbound chord: %s', concat(keys.chord, ' '))
end

B.insertmode  = function(keys) keys.mode = 'insert'  end
B.commandmode = function(keys) keys.mode = 'command' end

B.modes = {}
B.modes.insert, B.modes.command = {}, {}; do
  local I, C = B.modes.insert, B.modes.command
  I.fallback = 'insertChord'
  I.esc      = 'commandmode'

  C.fallback = 'unboundChord'
  C.esc      = 'commandmode'
  C.i        = 'insertmode'
end

---------------------------
-- Action and installation

M.action = function(data, ev, evsend)
  local ki = assert(ev.keyinput)
  local K, B = data.keys, data.bindings
  K.next = K.next or B.modes[K.mode]
  local n = type(K.next) == 'string' and K.next
    or K.next[ki] or B.modes[K.mode].fallback
  if type(n) == 'table' then K.next = n; return end
  if K.keep then K.keep = nil
  else
    K.chord, K.event = {}, {}
    K.next = B.modes[K.mode]
  end
  push(K.chord, ki)
  local ev = B[n](K)
  if ev then evsend(ev) end
end

-- set default bindings for data
M.defaultBindings = function(data)
end


M.install = function(data)

end

return M
