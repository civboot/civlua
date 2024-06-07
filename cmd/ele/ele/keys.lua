-- Keys builin plugin
local M = mod and mod'keys' or {}

local push = table.insert

M.action = function(data, ev, events)
  local keyinput = assert(ev.keyinput)
  local K = data.keys
  push(K.chord, keyinput)
  local n = type(K.next) == 'string' and K.next
    or K.next[keyinput] or K.fallback
  if type(n) == 'table' then K.next = n; return end
  if K.keep then K.keep = nil
  else
    K.chord, K.event = {}, {}
    K.next = data.bindings.mode[K.mode]
  end
  local ev = data.bindings[n](K)
  if ev then events:push(ev) end
end

return M
