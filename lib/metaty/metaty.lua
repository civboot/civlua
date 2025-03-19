local G = G or _G

--- metaty: simple but effective Lua type system using metatable
local M = G.mod and G.mod'metaty' or setmetatable({}, {})
local concat = table.concat

-- FIXME(netbsd): metaty isn't loading .so
do
  local treq = function(n) --> try to require n from metaty.native
    local ok, o = pcall(function() return require'metaty.native'[n] end)
    if ok then return o end
  end
  string.concat = treq'concat'
  or function(sep, ...) return concat({...}, sep) end

  table.update = table.update or treq'update'
  or function(t, update)
    for k, v in pairs(update) do t[k] = v end; return t
  end

  table.push = table.push or treq'push'
  or function(t, v) local i = #t + 1; t[i] = v; return i end
end

local srep = string.rep
local sfmt = string.format

local push, update = table.push, table.update

---------------
-- Pre module: environment variables
local IS_ENV = { ['true']=true,   ['1']=true,
                 ['false']=false, ['0']=false, ['']=false }
local EMPTY = {}

--- isEnv: returns boolean for below values, else nil
M.isEnv = function(var)
  var = os.getenv(var); if var then return IS_ENV[var] end
end
M.isEnvG = function(var) -- is env or globals
  local e = M.isEnv(var); if e ~= nil then return e end
  return G[var]
end
local CHECK  = M.isEnvG'METATY_CHECK' or false -- private
M.getCheck = function() return CHECK end

--- get method of table if it exists.
--- This first looks for the item directly on the table, then the item
--- in the table's metatable. It does NOT use the table's normal [$__index].
M.getmethod = function(t, method)
  return rawget(t, method) or rawget(getmetatable(t) or EMPTY, method)
end

---------------
-- general functions and constants
M.DEPTH_ERROR = '{!max depth reached!}'

M.ty = function(o) --> Type: string or metatable
  local t = type(o)
  return t == 'table' and getmetatable(o) or t
end

--- Given a type return it's name
M.tyName = function(T, default) --> string
  local Tty = type(T)
  return Tty == 'string' and T
    or ((Tty == 'table') and rawget(T, '__name'))
    or default or Tty
end

--- Given an object (function, table, userdata) return its name.
--- return nil if it's not one of the above types
M.name = function(o)
  local ty = type(o)
  return ty == 'function' and M.fninfo(o)
      or ty == 'table'    and M.tyName(M.ty(o))
      or ty == 'userdata' and M.tyName(getmetatable(o), 'userdata')
      or ty
end

M.callable = function(obj) --> bool: return if obj is callable
  if type(obj) == 'function' then return true end
  local m = getmetatable(obj)
  return m and rawget(m, '__call') and true
end
M.metaget = function(t, k)   return rawget(getmetatable(t), k) end

--- keywords https://www.lua.org/manual/5.4/manual.html
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
    info = info or debug.getinfo(fn, 'Sl'); loc = info.source
    if loc:sub(1,1) == '@' then
      loc = loc:sub(2)..':'..info.linedefined
    else loc = nil end
  end
  return name or 'function', loc
end

--- You probably want split instead.
--- Usage: [$for ctx, line in rawsplit, text, {'\n', 1} do]
M.rawsplit = function(subj, ctx) --> (state, splitstr)
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

--- split the subj by pattern. [$ctx] has two keys: [$si] (start index) and
--- [$ei] (end index)
--- [{## lang=lua}
--- for ctx, line in split(text, '\n') do -- split lines
---   ... do something with line
--- end
--- ]##
M.split = function(subj, pat--[[%s+]], index--[[1]]) --> (cxt, str) iter
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

--- compare tables or anything else
M.eq = function(a, b) return NATIVE_TY_EQ[type(a)](a, b) end --> bool

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
M.extendFields = function(fields, ids, docs, R)
  for i=1,#R do
    local spec = rawget(R, i); rawset(R, i, nil)
    -- name [type] : some docs, but [type] and ':' are optional.
    local name, tyname, fdoc =
        spec:match'^([%w_]+)%s*(%b[])%s*:?%s*(.*)$'
    if not name then -- check for {type}
      name, tyname, fdoc =
        spec:match'^([%w_]+)%s*(%b{})%s*:?%s*(.*)$'
    end
    if not name then
      name, fdoc = spec:match'^([%w_]+)%s*:?%s*(.*)$'
    end
    assert(name,      'invalid spec')
    assert(#name > 0, 'empty name')
    push(fields, name); fields[name] = tyname or true
    local id, iddoc = fdoc:match'^%s*#(%d+)%s*:?%s*(.*)$'
    if id then
      id = tonumber(id); fdoc = iddoc
      if ids[id] or ids[name] then
        error('id specified multiple times: '..name)
      end
      ids[name] = id; ids[id] = name
    end
    docs[name] = (fdoc ~= '') and fdoc or nil
  end
  return fields, ids, docs
end

M.namedRecord = function(name, R, loc)
  rawset(R, '__name', name)
  local fieldIds = {}; for id in ipairs(R.reserved or {}) do
    fieldIds[id] = id
  end; R.reserved = nil
  R.__fields, R.__fieldIds, R.__docs = M.extendFields({}, fieldIds, {}, R)
  R.__index  = rawget(R, '__index') or R
  local mt = {
    __name='Ty<'..R.__name..'>',
    __newindex=mod and mod.__newindex,
    __tostring=function() return R.__name end,
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

M.record = function(name)
  assert(type(name) == 'string' and #name > 0,
         'must set name to string')
  return function(R) return M.namedRecord(name, R) end
end

M.isRecord = function(t)
  if type(t) ~= 'table' then return false end
  local mt = getmetatable(t)
  return mt and mt.__name and mt.__name:find'^Ty<'
end


--- Extend the Type with (optional) new name and (optional) additional fields.
M.extend = function(Type, name, fields)
  name, fields = name or Type.__name, fields or {}
  local E, mt = update({}, Type), update({}, getmetatable(Type))
  E.__name, mt.__name = name, 'Ty<'..name..'>'
  E.__index = E
  E.__fields   = update({}, E.__fields);
  E.__fieldIds = update({}, E.__fieldIds);
  E.__fields, E.__fieldIds, E.__docs = M.extendFields(
    update({}, E.__fields),
    update({}, E.__fieldIds),
    update({}, E.__docs),
    fields
  )
  for k, v in pairs(fields) do E[k] = v end
  return setmetatable(E, mt)
end

M.enum_tostring = function(E) return E.__name end
M.enum_toPod = function(E, pset, e)
  if pset.enumIds then return E.id(e) else return E.name(e) end
end
M.enum_fromPod = function(E, pset, e) return E.name(e) end
M.enum_partialMatcher = function(E, fnMap)
  for name, fn in pairs(fnMap) do
    if not E.__names[name] then error(name..' is not in enum '..E.__name) end
    if not M.callable(fn) then error(name ..'is not callable') end
  end
  for name, id in pairs(E.__names) do
    if fnMap[name] then fnMap[id] = fnMap[name] end
  end
  return fnMap
end
M.enum_matcher = function(E, fnMap)
  local missing = {}
  for name in pairs(E.__names) do
    if not fnMap[name] then push(missing, name) end
  end
  if #missing > 0 then
    error('missing variants (or set default): '
          ..table.concat(missing, ' '))
  end
  return E:partialMatcher(fnMap)
end

local ENUM_INVALID = {id=1, name=1, matcher=1, partialMatcher=2}
M.namedEnum = function(ename, nameIds)
  local names, ids = {}, {}
  for name, id in pairs(nameIds) do
    assert(type(name) == 'string' and #name > 0,
      'keys must be string names')
    assert(math.type(id) == 'integer' and id >= 0,
      'values must be integer ids greater >= 0')
    assert(not ENUM_INVALID[name], 'must not name variant id, name')
    assert(name:sub(1,2) ~= '__', "name must not start with '__'")
    names[name] = name; names[id] = name
    ids[name]   = id;   ids[id]   = id
  end
  local errmsg = ' is not a variant of enum '..ename
  local E = {
    __name = ename,
    __names=nameIds,
    name = function(v) return names[v]
                       or error(tostring(v)..errmsg) end,
    id = function(v) return ids[v]
                     or error(tostring(v)..errmsg) end,
    __tostring = M.enum_tostring,
    matcher = M.enum_matcher, partialMatcher = M.enum_partialMatcher,
  }
  for name in pairs(nameIds) do E[name] = name end
  E.__toPod, E.__fromPod = M.enum_toPod, M.enum_fromPod
  return setmetatable(E, {
    __name = ename, __tostring = E.__tostring,
    __index = function(k) error(sfmt(
      'enum %s has no method %s', ename, k
    )) end
  })
end

--- Create an enum type which can convert between string and integers.
---
--- This "type" is mainly to allow typosafe enums, both when creating the variant
--- (i.e. [$v = MyEnum.VARIANT]) and when matching using the [$matcher] method below.
--- It also allows using checked enums in [$ds.pod].
---
--- One of the main benefits of using an enum is to ensure that when you are
--- matching you don't make a typo mistake (i.e. WOKER instead of WORKER). In
--- lua there is no native [$switch] statement (or similar), but table lookup
--- on functions can be equally as good -- see the example below.
---
--- [{h2}Example]
--- [{### lang=lua}
--- M.Job = enum'Job' {
---   OWNER   = 1,
---   MANAGER = 2,
---   COOK    = 3,
---   WAITER  = 4,
--- }
---
--- assert('OWNER', M.Job.OWNER)
---
--- -- either string or id will return string
--- assert('OWNER', M.Job.name(1))
--- assert('OWNER', M.Job.name('OWNER'))
---
--- -- either string or id will return id
--- assert(1, M.Job.id(1))
--- assert(1, M.Job.id('OWNER'))
---
--- -- create a table that converts a variant (name or id) -> function.
--- local doJob = M.Job:matcher {
---   OWNER   = function() print'tell them to get to work' end,
---   MANAGER = function() print'get to work!'             end,
---   COOK    = function() print'order up!'                end,
---   WAITER  = function() print'they want spam and eggs'  end,
---
---   -- Removing any of the above will cause an error that not all variants
---   -- are covered. You can use :partialMatcher if you want to
---   -- return nil instead.
---   --
---   -- Below will cause an error: no variant DISHWASHER
---   DISHWASHER = function() end
--- }
---
--- -- call in your own function like:
--- doJob[job](my, args)
--- ]###
---
M.enum = function(name)
  assert(type(name) == 'string' and #name > 0,
        'must name the enum using a string')
  return function(nameIds) return M.namedEnum(name, nameIds) end
end

getmetatable(M).__call = function(T, name) return M.record(name) end
return M
