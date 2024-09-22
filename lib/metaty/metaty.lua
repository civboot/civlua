local G = G or _G

-- metaty: simple but effective Lua type system using metatable
--
-- See README.md for documentation.
local M = (G.mod and G.mod'metaty' or {})
setmetatable(M, getmetatable(M) or {})

local function copy(t)
  local o = {}; for k, v in pairs(t) do o[k] = v end; return o
end

local concat = table.concat
local srep = string.rep
string.concat = string.concat or function(...)
  return select('#', ...) > 1 and concat{...} or (...) or ''
end
M.strcon = string.concat; local strcon = string.concat

---------------
-- Pre module: environment variables
local IS_ENV = { ['true']=true,   ['1']=true,
                 ['false']=false, ['0']=false, ['']=false }
local EMPTY = {}

-- isEnv: returns boolean for below values, else nil
M.isEnv = function(var)
  var = os.getenv(var); if var then return IS_ENV[var] end
end
M.isEnvG = function(var) -- is env or globals
  local e = M.isEnv(var); if e ~= nil then return e end
  return G[var]
end
local CHECK  = M.isEnvG'METATY_CHECK' or false -- private
M.getCheck = function() return CHECK end

-- get method of table if it exists.
-- This first looks for the item directly on the table, then the item
-- in the table's metatable. It does NOT use the table's normal __index
-- as many of them will fail.
M.getmethod = function(t, method)
  return rawget(t, method) or rawget(getmetatable(t) or EMPTY, method)
end

---------------
-- general functions and constants
M.DEPTH_ERROR = '{!max depth reached!}'
local add, sfmt = table.insert, string.format

M.ty = function(o) --> Type: string or metatable
  local t = type(o)
  return t == 'table' and getmetatable(o) or t
end

-- Given a type return it's name
M.tyName = function(T, default) --> name
  local Tty = type(T)
  return Tty == 'string' and T
    or ((Tty == 'table') and rawget(T, '__name'))
    or default or Tty
end

-- Given an object (function, table, userdata) return it's name.
-- return nil if it's not one of the above types
M.name = function(o)
  local ty = type(o)
  return ty == 'function' and M.fninfo(o)
      or ty == 'table'    and M.tyName(M.ty(o))
      or ty == 'userdata' and M.tyName(getmetatable(o), 'userdata')
      or ty
end

M.callable = function(obj) --> bool: return if obj is callable
  if type(obj) == 'function' then return true end
  local m = getmetatable(obj); return m and rawget(m, '__call')
end
M.metaget = function(t, k)   return rawget(getmetatable(t), k) end

-- keywords https://www.lua.org/manual/5.4/manual.html
M.KEYWORD = {}; for kw in string.gmatch([[
and       break     do        else      elseif    end
false     for       function  goto      if        in
local     nil       not       or        repeat    return
then      true      until     while
]], '%w+') do M.KEYWORD[kw] = true end

M.validKey = function(s) --> boolean: s=value is valid syntax
  return type(s) == 'string' and
    not (M.KEYWORD[s] or tonumber(s)
         or s:find'[^_%w]')
end

M.fninfo = function(fn)
  local info
  local name = PKG_NAMES[fn]; if not name then
    info = debug.getinfo(fn)
    name = info.name
  end
  local loc = PKG_LOC[fn]; if not loc then
    info = info or debug.getinfo(fn)
    loc = string.format('%s:%s', info.short_src, info.linedefined)
  end
  return name or 'function', loc
end

-- rawsplit(subj, ctx) -> (ctx, splitstr)
-- Note: prefer split
--
--   for ctx, line in rawsplit, text, {'\n', 1} do ... end
M.rawsplit = function(subj, ctx)
  local pat, i = table.unpack(ctx)
  if not i then return end
  if i > #subj then
    ctx.si, ctx.ei, ctx[2] = #subj+1, #subj, nil
    return ctx, ''
  end
  local s, e = subj:find(pat, i)
  ctx.si, ctx.ei, ctx[2] = i, (s and (s-1)) or #subj, e and (e+1)
  return ctx, subj:sub(ctx.si, ctx.ei)
end

-- split(subj:str, pat="%s+", index=1) -> iterator (ctx, str)
-- split the subj by pattern.
-- ctx has two keys: si (start index) and ei (end index)
--
-- Eample:
--   for ctx, line in split(text, '\n') do -- split lines
--     ... do something with line
--   end
M.split = function(subj, pat, index)
  return M.rawsplit, subj, {pat or '%s+', index or 1}
end

-----------------------------
-- Equality
M.nativeEq = function(a, b) return a == b end
local NATIVE_TY_EQ = {
  number   = rawequal,   boolean = rawequal, string = rawequal,
  userdata = M.nativeEq, thread  = M.nativeEq,
  ['nil']  = rawequal,   ['function'] = rawequal,
  ['table'] = function(a, b)
    if a == b then return true end
    local mt = getmetatable(a)
    if type(mt) == 'table' and rawget(mt, '__eq') then
      return false -- true equality already tested
    end
    return M.eqDeep(a, b)
  end,
}
M.eqDeep = function(a, b)
  if rawequal(a, b)     then return true   end
  if M.ty(a) ~= M.ty(b) then return false  end
  local aLen, eq = 0, M.eq
  for aKey, aValue in pairs(a) do
    local bValue = b[aKey]
    if not M.eq(aValue, bValue) then return false end
    aLen = aLen + 1
  end
  local bLen = 0
  -- Note: #b only returns length of integer indexes
  for bKey in pairs(b) do bLen = bLen + 1 end
  return aLen == bLen
end

-- eq(a, b) -> bool: compare tables or anything else
M.eq = function(a, b) return NATIVE_TY_EQ[type(a)](a, b) end

-----------------------
-- record
M.indexError = function(R, k, lvl) -- note: can use directly as mt.__index
  error(R.__name..' does not have field '..k, lvl or 2)
end
M.index = function(R, k) -- Note: R is record's metatable
  if type(k) == 'string' and not rawget(R, '__fields')[k] then
    M.indexError(R, k, 3)
  end
end
M.newindex = function(r, k, v)
  if type(k) == 'string' and not M.metaget(r, '__fields')[k] then
    M.indexError(getmetatable(r), k, 3)
  end
  rawset(r, k, v)
end

M.fieldsCheck = function(T, fields, t)
  local tkey; while true do
    tkey = next(t, tkey); if not tkey then return end
    if type(tkey) == 'string' and not fields[tkey] then
      error(sfmt('[%s] unrecognized field: %s', T.__name, tkey))
    end
  end
end
M.constructChecked = function(T, t)
  M.fieldsCheck(T, rawget(T, '__fields'), t)
  return setmetatable(t, T)
end
M.constructUnchecked = function(T, t)
  return setmetatable(t, T)
end
M.construct = (CHECK and M.constructChecked) or M.constructUnchecked
M.extendFields = function(fields, R)
  local docs = {}
  for i=1,#R do
    local spec = rawget(R, i); rawset(R, i, nil)
    -- name [type] : some docs, but [type] and ':' are optional.
    local name, tyname, fdoc =
      spec:match'^([%w_]+)%s*(%b[])%s*:?%s*(.*)$'
    if not name then
      name, fdoc = spec:match'^([%w_]+)%s*:?%s*(.*)$'
    end
    assert(name,      'invalid spec')
    assert(#name > 0, 'empty name')
    add(fields, name); fields[name] = tyname or true
    docs[name] = fdoc ~= '' and fdoc or nil
  end
  return fields, docs
end

M.namedRecord = function(name, R, loc)
  rawset(R, '__name', name)
  R.__fields, R.__docs = M.extendFields({}, R)
  R.__index  = rawget(R, '__index') or R
  local mt = {
    __name='Ty<'..R.__name..'>',
    __newindex=mod and mod.__newindex,
  }
  local R = setmetatable(R, mt)
  if G.METATY_CHECK then
    mt.__call    = M.constructChecked
    mt.__index   = M.index
    rawset(R, '__newindex', rawget(R, '__newindex') or M.newindex)
  else
    mt.__call = M.constructUnchecked
  end
  return R
end

M.isRecord = function(t)
  if type(t) ~= 'table' then return false end
  local mt = getmetatable(t)
  return mt and mt.__name and mt.__name:find'^Ty<'
end

M.record = function(name)
  assert(type(name) == 'string' and #name > 0,
         'must set __name=string')
  return function(R) return M.namedRecord(name, R) end
end
assert(not getmetatable(M).__call)
getmetatable(M).__call = function(T, name)
  return M.record(name)
end

-- Extend the Type with (optional) new name and (optional) additional fields.
M.extend = function(Type, name, fields)
  name, fields = name or Type.__name, fields or {}
  local E, mt = copy(Type), copy(getmetatable(Type))
  E.__name, mt.__name = name, 'Ty<'..name..'>'
  E.__index = E
  E.__fields = copy(E.__fields); M.extendFields(E.__fields, fields)
  for k, v in pairs(fields) do E[k] = v end
  return setmetatable(E, mt)
end

return M
