print('!! loading pod')
local G = G or _G
--- pod: plain old data
local M = G.mod and mod'pod' or setmetatable({}, {})
local N = require'pod.native'

local mty = require'metaty'

local push = table.insert
local ser, deser = N.ser, N.deser
local mtype = math.type
local sfmt = string.format

--- Pod: configuration for converting values to/from POD.
M.Pod = mty'Pod'{
  'fieldIds [boolean]: if true use the fieldIds when possible',
  'mtPodFn  [(mt) -> boolean]: function to classify if mt is pod',
    mtPodFn = function() end,
  'enumIds [boolean]: if true use enum id variants, else name variants',
}
local Pod = M.Pod
Pod.DEFAULT = Pod{}
local CONCRETE = { boolean=true, number=true, string=true }
local BUILTIN = table.update(table.update({}, CONCRETE), {
  ['nil']=true, table=true
})
M.isConcrete = function(v) return CONCRETE[type(v)] end

-- return true if the value is "plain old data".
--
-- Plain old data is defined as any native type or a table with no metatable
-- and who's pairs() are only POD.
local isPod; isPod = function(v, mtFn)
  local ty = type(v); if ty == 'table' then
    local mt = getmetatable(v); if mt then return mtFn(v, mt) end
    for k, v in pairs(v) do
      if not (isPod(k, mtFn) and isPod(v, mtFn)) then
        return false
      end
    end
    return true
  end
  return BUILTIN[ty]
end
M.isPod = isPod

--- A type who's sole job is converting values to/from POD.
M.Podder = mty'Podder' {
  'name [string]',
  '__toPod   [(self, pset, v) -> p]',
  '__fromPod [(self, pset, p) -> v]',
}
M.Podder.__tostring = function(p) return p.name end

local makeNativePodder = function(ty)
  local expected = 'expected '..ty
  local f = function(self, pod, v)
    if v == nil then return end
    if type(v) ~= ty then error(sfmt(
      'expected %s got %s', ty, type(v))
    )end
    return v
  end
  return M.Podder{name=ty, __toPod=f, __fromPod=f}
end
local tpInt = function(self, pod, i)
  if i == nil then return end
  if mtype(i) ~= 'integer' then error('expected integer got '..type(i)) end
  return i
end

local BUILTIN_PODDER = {
  ['nil'] = makeNativePodder'nil',
  boolean = makeNativePodder'boolean',
  number = makeNativePodder'number',
  string = makeNativePodder'string',
  table = makeNativePodder'table',
  integer = M.Podder{
    name='integer', __toPod=tpInt, __fromPod=tpInt,
  },
}
BUILTIN_PODDER.table.__toPod = function(T, pod, t)
  if type(t) ~= 'table' then error('expected table got '..type(t)) end
  assert(isPod(t, pod.mtPodFn), 'table is not plain-old-data')
  return t
end
BUILTIN_PODDER.int = BUILTIN_PODDER.integer
BUILTIN_PODDER.str = BUILTIN_PODDER.string

for k, p in pairs(BUILTIN_PODDER) do M[k] = p end
M['nil'], M.nil_ = nil, BUILTIN_PODDER['nil']

--- Handles concrete non-nil types (boolean, number, string)
M.key = mty'key' {}
M.key.__toPod = function(self, pod, v)
  if CONCRETE[type(v)] then return v end
  error('nonconrete type: '..type(v))
end
M.key.__fromPod = M.key.__toPod
BUILTIN_PODDER.key = M.key

--- Handles all native types (nil, boolean, number, string, table)
M.builtin = mty'builtin' {}; local builtin = M.builtin
builtin.__toPod = function(self, pod, v)
  local ty = type(v)
  if ty == 'table' then
    assert(isPod(v, pod.mtPodFn), 'table is not plain-old-data')
    return v
  elseif BUILTIN[ty]   then return v end
  error('nonnative type: '..type(v))
end
builtin.__fromPod = function(self, pod, v)
  if BUILTIN[type(v)] then return v end
  error('nonbuiltin type: '..type(v))
end
BUILTIN_PODDER.builtin = builtin

--- Poder for a list of items with a type.
M.List = mty'List' {'I [Podder]: the type of each list item'}
M.List.__toPod = function(self, pod, l)
  local I, p = self.I, {}
  for i, v in ipairs(l) do p[i] = I:__toPod(pod, v) end
  return p
end
M.List.__fromPod = function(self, pod, p)
  local I, l = self.I, {}
  for i, v in ipairs(l) do l[i] = I:__fromPod(pod, v) end
  return l
end

--- Poder for a map of key/value pairs.
M.Map = mty'Map' {
  'K [Podder]: keys type', K=M.key,
  'V [Podder]: values type',
}
M.Map.__toPod = function(self, pod, m)
  local K, V, p = self.K, self.V, {}
  for k, v in pairs(m) do
    p[K:__toPod(pod, k)] = V:__toPod(pod, v)
  end
  return p
end
M.Map.__fromPod = function(self, pod, p)
  local K, V, m = self.K, self.V, {}
  for k, v in pairs(p) do
    m[K:__fromPod(pod, k)] = V:__fromPod(pod, v)
  end
  return m
end

M.toPod = function(v, podder, pod)
  if not podder then
    local ty = type(v)
    if ty == 'table' then
      podder = getmetatable(v) or M.table
      if podder == 'table' then podder = M.table end
    else
      podder = BUILTIN_PODDER[ty] or error('not pod: '..ty)
    end
  end
  return podder:__toPod(pod or Pod.DEFAULT, v)
end
M.fromPod = function(v, poder, pod)
  return (poder or builtin):__fromPod(pod or Pod.DEFAULT, v)
end
local toPod, fromPod = M.toPod, M.fromPod

--- Default __toPod for metatype records
M.mty_toPod = function(T, pod, t)
  local p, podders = {}, T.__podders
  if pod.fieldIds then
    local fieldIds = T.__fieldIds
    for field, field in ipairs(T.__fields) do
      local v = rawget(t, field); if v ~= nil then
        p[fieldIds[field]] = podders[field]:__toPod(pod, v)
      end
    end
  else
    for _, field in ipairs(T.__fields) do
      local v = rawget(t, field); if v ~= nil then
        p[field]           = podders[field]:__toPod(pod, v)
      end
    end
  end
  return p
end

--- Default __fromPod for metatype records
M.mty_fromPod = function(T, pod, p)
  local t, podders, fieldIds = {}, T.__podders, T.__fieldIds
  for k, v in pairs(p) do
    if type(k) == 'number' then k = fieldIds[k] end
    t[k] = podders[k]:__fromPod(pod, v)
  end
  return T(t)
end

--- lookup podder from types, native, PKG_LOOKUP
local lookupPodder = function(T, types, name)
  if G.PKG_NAMES[T] == name then return T end
  local p = types[name] or BUILTIN_PODDER[name] or G.PKG_LOOKUP[name]
         or error('Cannot find type '..name)
  if not (p.__toPod and p.__fromPod) then
    error(name.." doesn't implement both __toPod and __fromPod")
  end
  return p
end

--- Make metaty type convertable to/from plain-old-data
---
--- Typically this is called by calling the module itself,
--- i.e. [$pod(mty'myType'{'field [int]#1'})]
M.implPod = function(T, tys)
  tys = tys or {}
  local errs, podders, podder = {}, {}, nil
  for _, field in ipairs(T.__fields) do
    local tyname = T.__fields[field]
    if type(tyname) ~= 'string' then
      push(errs, field..' does not have tyname specified') end
    if tyname:match'%b[]' then
      podder = lookupPodder(T, tys, tyname:sub(2,-2))
    elseif tyname:match'%b{}' then
      tyname = tyname:sub(2,-2)
      local kname, vname = tyname:match'^%s*(.-)%s*:%s*(.-)%s*$'
      if kname then
        podder = M.Map {
          K=lookupPodder(T, tys, kname), V=lookupPodder(T, tys, vname),
        }
      else podder = M.List{I=lookupPodder(T, tys, tyname)} end
    else error('unrecognized tyname: '..tyname) end
    podders[field] = podder
  end
  if #errs > 0 then error(sfmt(
    'Errors: \n * %s\n', table.concat(errs, '\n * ')
  ))end
  T.__podders = podders
  T.__toPod = M.mty_toPod
  T.__fromPod = M.mty_fromPod
  return T
end

--- serialize the value (without calling toPod on it)
M.serRaw = N.ser--(value) --> string

--- deserialize the value (without calling fromPod on it)
M.deserRaw = N.deser--(string) --> value

--- Serialize value, converting it to a compact string.
--- Note: this function first calls toPod on the value.
M.ser = function(value) --> string
  return ser(toPod(value))
end

--- Deserialize value from a compact string (and call fromPod on it)
--- [$index] (default=1) is where to start in [$str]
M.deser = function(str, P, index) --> value, lenUsed
  local p, elen = deser(str, index)
  return fromPod(p, P), elen
end

getmetatable(M).__call = function(M, ...) return M.implPod(...) end
print('!! loaded pod')
return M
