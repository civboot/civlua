-- pod: convert types from/to plain old data (pod)
--
-- This module exports the toPod() and fromPod() functions for serialization
-- libraries to use. These convert a metaty value (or lua concrete value)
-- to/from plain old data and add the configurable TYPE_KEY (default='??') for
-- deserializing the type.
--
-- A (metatable) type can support these methods by by supporting the methods
-- __fromPod() and __toPod(). This module provides metaty defaults for these
-- methods that should work for most simple metadta types that are already PoD
-- (PoD). You can make your type as serializable with:
--
--   local pod = require'ds.pod'
--   MyType = mty'MyType' { ... }
--   pod(MyType)
--   -- Or simply:
--   MyType.__toPod, MyType.__fromPod = pod.__toPod, pod.__fromPod
--
-- Alternatively, you can implement these methods yourself. See
-- the requirements in the function documentation.
local M = pkg and pkg'ds.serde' or {}

M.TYPE_KEY = '??'
-- M.TYPE_KEY = '__type'

local ds = require'ds'
local getmt = getmetatable
local icopy, popk, none = ds.icopy, ds.popk

local toPod, fromPod, TO_POD, FROM_POD

-- Serialize value t into plain old data
M.toPod = function(val) return TO_POD[type(val)](val) end --> PoD
toPod = M.toPod

-- Depod plain old data into metaty
M.fromPod = function(pod) --> value
  return (FROM_POD[type(pod)] or error('unknown type: '..type(pod)))
    (pod)
end
fromPod = M.fromPod

M.TO_POD = { -- pod value into pod
  ['nil'] = ds.iden, boolean = ds.iden,
  number  = ds.iden, string  = ds.iden,
  table = function(t)
    local mt = getmt(t); if mt then
      if type(mt) == 'table' then
        return assert(mt.__toPod, 'does not implement pod')(t)
      end
      if mt ~= 'table' then return t end -- is a sentinel
    end
    local out = {}; for k, v in pairs(t) do out[k] = toPod(v) end
    return out
  end,
}
TO_POD = M.TO_POD

M.FROM_POD = { -- fromPod pod into value
  ['nil'] = ds.iden, boolean = ds.iden,
  number  = ds.iden, string  = ds.iden,
  table = function(t)
    local ty = rawget(t, M.TYPE_KEY)
    return ty and PKG_LOOKUP[ty]:__fromPod(t) or t
  end,
}
FROM_POD = M.FROM_POD

-- Default metaty __toPod method.
--
-- Convert an type instance to a plain table. The returned table must be only
-- plain old data composed of only bool, number, string or non-metatable
-- values.
--
-- The returned table has a TYPE_KEY field which can be used with PKG_LOOKUP.
M.__toPod = function(self) --> table
  local t, mt = icopy(self), getmt(self)
  t[M.TYPE_KEY] = PKG_NAMES[mt]
  for k in pairs(mt.__fields) do t[k] = toPod(rawget(self, k)) end
  return t
end

-- Default metaty __fromPod method.
--
-- This implementation converts a table of PoD to the metaty by first
-- converting it's fields (except TYPE_KEY) and then using
-- getmetatable(T).__call to construct it.
--
-- To use this, the metatable.call method must be able to handle the plain
-- data input, otherwise you need to implement this method yourself.
M.__fromPod = function(T, pod) --> value
  local t = {}; for k, v in pairs(pod) do t[k] = fromPod(v) end
  rawset(t, M.TYPE_KEY, nil)
  return T(t)
end

if not getmetatable(M) then setmetatable(M, {}) end
getmetatable(M).__call = function(_, T)
  assert(PKG_NAMES[T], 'not in PKG_NAMES')
  T.__toPod, T.__fromPod = M.__toPod, M.__fromPod
end

return M
