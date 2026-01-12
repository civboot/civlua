local concat = table.concat
local getmt, type, rawget = getmetatable, type, rawget

local srep = string.rep
local sfmt = string.format
local push = table.insert
local rawget, rawset = rawget, rawset
local _G = _G

rawset(_G, 'LUA_OPT', rawget(_G, 'LUA_OPT')
                   or tonumber(os.getenv'LUA_OPT' or 1))

local CONCRETE = {
  ['nil']=true, bool=true, boolean=true,
  number=true,  string=true,
}
local BUILTIN = {table=true}
for k,v in pairs(CONCRETE) do BUILTIN[k] = v end

local G = setmetatable({}, {
  __name='G(init globals)',
  __index    = function(_, k)    return rawget(_G, k)    end,
  __newindex = function(g, k, v) return rawset(_G, k, v) end,
})

-- Documentation globals
-- FIXME: rename these MOD_*
local weakk, weakv = {__mode='k'}, {__mode='v'}
G.PKG_NAMES  = G.PKG_NAMES  or setmetatable({}, weakk) -- obj -> name
G.PKG_LOC    = G.PKG_LOC    or setmetatable({}, weakk) -- obj -> path:loc
G.PKG_LOOKUP = G.PKG_LOOKUP or setmetatable({}, weakv) -- name -> obj

local srcloc = function(level)
  local info = debug.getinfo(2 + (level or 0), 'Sl')
  local loc = info.source; if loc:sub(1,1) ~= '@' then return end
  return loc:sub(2)..':'..info.currentline
end

local mod; mod = {
  __name = 'Mod',
  __index = function(m, k) error('mod does not have: '..k, 2) end,
  __newindex = function(m, k, v)
    rawset(m, k, v)
    if type(k) ~= 'string' then return end
    push(m.__attrs, k)
    local n = rawget(m, '__name')
    mod.save(m.__name..'.'..k, v)
  end,
}

-- member function (not method)
-- save v with name to PKG variables
mod.save = function(name, v)
  if CONCRETE[type(v)] then return end
  PKG_LOC[v]       = PKG_LOC[v]       or srcloc(2)
  PKG_NAMES[v]     = PKG_NAMES[v]     or name
  PKG_LOOKUP[name] = PKG_LOOKUP[name] or v
end

setmetatable(mod, {
  __name='Mod',
  __call=function(T, name)
    assert(type(name) == 'string', 'must provide name str')
    local m = setmetatable({
      __name=name,
      __attrs={}, -- ordered attributes added after
      __doc=function(self, d) d:mod(self) end,
    }, {
      __name=sfmt('Mod<%s>', name),
      __index=mod.__index,
      __newindex=mod.__newindex,
      __tostring=function(m) return m.__name end
    })
    mod.save(name, m)
    return m
  end,
})

--- metaty: simple but effective Lua type system using metatable
local M = mod'metaty'

--- G allows assignment to globals and returns nil if a variable is missing.
---
--- Calling [$metaty.setup()] makes non-G globals typosafe.
M.G = G

-- mod: create typosafe mod.
--
-- usage: [$local M = mod'name']
M.mod = mod
M.isMod = function(t) --> boolean
  if type(t) ~= 'table' then return false end
  local mt = getmetatable(t)
  return mt and mt.__name and mt.__name:find'^Mod<'
end

-- TODO: remove these globals
G.G = G.G or G
G.mod = mod

local noG = function(_, k)
  error(sfmt(
    'global %s is nil/unset. Initialize with G.%s = non_nil_value', k, k
  ), 2)
end
--- Setup lua's global environment to meet metaty protocol.
---
--- Currently this only makes non-[$G] global access typosafe (throw error if
--- not previously set).
M.setup = function()
  setmetatable(_G, {
    __name='_G(metatable by metaty)',
    __index=noG, __newindex=noG,
  })
end

local update = function(t, update)
  for k, v in pairs(update) do t[k] = v end; return t
end

-- set of concrete types
M.CONCRETE, M.BUILTIN = CONCRETE, BUILTIN
M.isConcrete = function(v) return CONCRETE[type(v)] end
M.isBuiltin = function(obj)
  return M.isConcrete(obj) or (obj == nil) or (getmetatable(obj) == nil)
end

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

--- get method of table if it exists.
--- This first looks for the item directly on the table, then the item
--- in the table's metatable. It does NOT use the table's normal [$__index].
M.getmethod = function(t, method)
  return rawget(t, method) or rawget(getmt(t) or EMPTY, method)
end

---------------
-- general functions and constants
M.DEPTH_ERROR = '{!max depth reached!}'

--- Get the type of the value.
M.ty = function(v) --> type: string or metatable
  local t = type(v)
  return t == 'table' and getmt(v) or t
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
      or ty == 'userdata' and M.tyName(getmt(o), 'userdata')
      or ty
end

M.callable = function(obj) --> bool: return if obj is callable
  if type(obj) == 'function' then return true end
  local m = getmt(obj)
  return m and rawget(m, '__call') and true
end
M.metaget = function(t, k)   return rawget(getmt(t), k) end

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

--- Extract name,loc from function value.
M.fninfo = function(fn) --> name, loc
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

--- Extract name,loc from any value (typically mod/type/function).
function M.anyinfo(v) --> name, loc
  if type(v) == 'function' then return M.fninfo(v) end
  if M.isBuiltin(v)        then return type(v), nil end
  local name, loc = PKG_NAMES[v], PKG_LOC[v]
  name = name or M.name(v)
  if loc and loc:find'%[' then loc = nil end
  return name, loc
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
--- [{$$ lang=lua}
--- for ctx, line in split(text, '\n') do -- split lines
---   ... do something with line
--- end
--- ]$
M.split = function(subj, pat--[[%s+]], index--[[1]]) --> (cxt, str) iter
  return M.rawsplit, subj, {pat or '%s+', index or 1}
end

--- The default __fmt method.
M.fmt = function(self, f)
  local mt = getmt(self)
  local len, fields = #self, rawget(mt, '__fields')
  local multi = len + #fields > 1 -- use multiple lines
  f:write(rawget(mt, '__name'));
  f:level(1);  f:write(multi and f.tableStart or '{')
  f:items(self, #fields > 0,
          multi and (len>0) and (#fields>0) and f.listEnd)
  f:keyvals(self, fields)
  f:level(-1); f:write(multi and f.tableEnd or '}')
end

--- The default __tostring method.
M.tostring = function(self)
  local mt = getmt(self)
  return sfmt('%s@%p', rawget(mt, '__name'), self)
end

local function cleanupFieldTy(tyStr)
  return tyStr:match'%[(.*)%]' or tyStr
end

M._docFields = function(R, d, name, kind)
  local fmt = require'fmt'
  local fields = {}
  for _, fname in ipairs(R.__fields or EMPTY) do
    if not fname:match'^_' then push(fields, fname) end
  end
  if #fields > 0 then
    d:bold(kind..':'); d:write'[+\n'; 
    for _, fname in ipairs(fields) do
      d:write'* '; d:level(1)
      local fullName = sfmt('%s.%s', name, fname)
      d:write(sfmt('[{*name=%s}%s]', fullName, fname))
      local ty = fields[fname]; if type(ty) == 'string' then
        d:write' '; d:code(cleanupFieldTy(ty))
      end
      local default = rawget(R, fname); if default ~= nil then
        d:write' '
        if PKG_NAMES[default] then
          d:code('='..PKG_NAMES[default])
        else
          local dstr = fmt(default)
          d:code('='..(#dstr <= 16 and dstr
                    or (M.name(default)..'() instance')))
        end
      end
      local doc = R.__docs[fname]; if doc then
        d:check(fullName, doc)
        d:write'\n'; d:write(doc)
      end
      d:level(-1); d:write'\n'
    end
    d:write']\n'
  end
end

M._docMethods = function(R, d, name)
  local methods = {}
  for _, k in ipairs(R.__attrs) do
    if k:match'^_' then goto continue end
    local v = rawget(R, k)
    if M.callable(v) then
      push(methods, k); methods[k] = v
    end
    ::continue::
  end
  if #methods > 0 then
    d:bold'Methods'; d:write' [+\n'; 
    for _, name in ipairs(methods) do
      d:write'* '; d:level(1)
      d:declfn(methods[name], name, sfmt('%s.%s', R.__name, name))
      d:level(-1); d:write'\n'
    end
    d:write']\n'
  end
end

--- The default __doc method.
---
--- ["d is of type [$doc.Documenter].
---   Tests are in cmd/doc/test.lua ]
M.doc = function(R, d)
  d.done[R] = true
  local name, loc = M.anyinfo(R)
  local cmt, code = d:extractCode(loc)
  d:header(d.tyHeader, 'Record '..R.__name, name)
  -- Comments
  if cmt and #cmt > 0 then
    d:check(name, cmt)
    for _, c in ipairs(cmt) do
      d:write(c); d:write'\n'
    end
    d:write'\n'
  end
  M._docFields(R, d, name, 'Fields')
  M._docMethods(R, d, name)
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
    local mt = getmt(a)
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
  error(sfmt('%q is not a field of %s', k, R.__name), lvl or 2)
end

M.index = function(R, k) -- Note: R is record's metatable
  if type(k) == 'string' and not rawget(R, '__fields')[k] then
    M.indexError(R, k, 3)
  end
end
M.hardIndex = function(R, k)
  if type(k) ~= 'string' or not rawget(R, '__fields')[k] then
    M.indexError(R, k, 3)
  end
end
M.newindex = function(r, k, v)
  if type(k) == 'string' and not M.metaget(r, '__fields')[k] then
    M.indexError(getmt(r), k, 3)
  end
  rawset(r, k, v)
end
M.hardNewindex = function(r, k, v)
  if type(k) ~= 'string' or not M.metaget(r, '__fields')[k] then
    M.indexError(getmt(r), k, 3)
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
M.construct = (G.LUA_OPT <= 2 and M.constructChecked) or M.constructUnchecked
M.extendFields = function(fields, ids, docs, R)
  for i=1,#R do
    local spec = rawget(R, i); rawset(R, i, nil)
    -- name [type] : some docs, but [type] and ':' are optional.
    local name, tyname, fdoc =
        spec:match'^([%w_]+)%s*(%b[])%s*:?%s*(.-)%s*$'
    if not name then -- check for {type}
      name, tyname, fdoc =
        spec:match'^([%w_]+)%s*(%b{})%s*:?%s*(.*)%s*$'
    end
    if not name then
      name, fdoc = spec:match'^([%w_]+)%s*:?%s*(.-)%s*$'
    end
    if not name then error('invalid spec: '..spec) end
    if #name==0 then error('empty name: '..spec) end
    push(fields, name); fields[name] = tyname or true
    local id, iddoc = fdoc:match'^%s*#(%d+)%s*:?%s*(.*)%s*$'
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
  R.__fmt      = rawget(R, '__fmt')      or M.fmt
  R.__doc      = rawget(R, '__doc')      or M.doc
  R.__tostring = rawget(R, '__tostring') or M.tostring
  R.__index    = rawget(R, '__index')    or R
  R.__attrs    = rawget(R, '__attrs')    or {}
  local mtR = {
    __name     = 'Ty<'..R.__name..'>',
    __newindex = mod and mod.__newindex,
    __tostring = function() return R.__name end,
  }
  local R = setmetatable(R, mtR)
  if G.LUA_OPT <= 2 then
    mtR.__call    = M.constructChecked
    mtR.__index   = M.index
    rawset(R, '__newindex', rawget(R, '__newindex') or M.newindex)
  else
    mtR.__call = M.constructUnchecked
  end
  return R
end

--- Start a new record.
--- Alternatively, call the metaty module directly.
M.record = function(name)
  assert(type(name) == 'string' and #name > 0,
         'must set name to string')
  return function(R) return M.namedRecord(name, R) end
end

--- Start a new record which acts as a lua module (i.e. the file doesn't use
--- [$metaty.mod])
M.recordMod = function(name)
  return function(R)
    R = M.namedRecord(name, R)
    mod.save(R.__name, R)
    return R
  end
end

M.isRecord = function(t)
  if type(t) ~= 'table' then return false end
  local mt = getmt(t)
  return mt and mt.__name and mt.__name:find'^Ty<'
end

--- Extend the Type with (optional) new name and (optional) additional fields.
M.extend = function(Type, name, fields)
  assert(type(Type) == 'table' and getmt(Type), 'arg 1 must be Type')
  assert(type(name) == 'string',                'arg 2 must be name')
  name, fields = name or Type.__name, fields or {}
  local E, mt = update({}, Type), update({}, getmt(Type))
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
--- [{$$$ lang=lua}
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
--- ]$$
---
M.enum = function(name)
  assert(type(name) == 'string' and #name > 0,
        'must name the enum using a string')
  return function(nameIds) return M.namedEnum(name, nameIds) end
end

getmt(M).__call = function(T, name) return M.record(name) end
assert(M.setup)
return M
