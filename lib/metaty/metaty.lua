-- metaty: simple but effective Lua type system using metatable
--
-- See README.md for documentation.

DOC       = DOC       or {}
FIELD_DOC = FIELD_DOC or {}

local M = {}

M.metaget = function(t, k) return rawget(getmetatable(t), k) end

-- isEnv: returns boolean for below values, else nil
local IS_ENV = { ['true']=true,   ['1']=true,
                 ['false']=false, ['0']=false, ['']=false }
function M.isEnv(var)
  var = os.getenv(var); if var then return IS_ENV[var] end
end
function M.isEnvG(var) -- is env or globals
  local e = M.isEnv(var); if e ~= nil then return e end
  return _G[var]
end

local CHECK = M.isEnvG'METATY_CHECK' or false -- private
local _doc   = M.isEnvG'METATY_DOC'   or false -- private
M.getCheck = function() return CHECK end
M.getDoc   = function() return _doc end
M.FN_DOCS = {}

local add, sfmt = table.insert, string.format
function M.identity(v) return v end
function M.trim(subj, pat, index)
  pat = pat and ('^'..pat..'*(.-)'..pat..'*$') or '^%s*(.-)%s*$'
  return subj:match(pat, index)
end

function M.steal(t, k) local v = t[k]; t[k] = nil; return v end
function M.nativeEq(a, b) return a == b end
function M.docTy(ty_, doc)
  if not _doc then return ty_ end
  doc = M.trim(doc)
  if type(ty_) == 'function' then  M.FN_DOCS[ty_] = doc
  elseif type(ty_) == 'table' then rawset(ty_, '__doc', doc)
  else error('cannot document type '..type(doc)) end
  return ty_
end
function M.doc(doc)
  if not _doc then      return M.identity end
  return function(ty_) return M.docTy(ty_, doc) end
end
M.docTy(M.isEnvG,  'isEnvG"MY_VAR": isEnv but also checks _G')
M.docTy(M.isEnv,  [[isEnv"MY_VAR" -> boolean (environment variable)
  true: 'true' '1'    false: 'false' '0' '']])
M.docTy(M.steal,   'steal(t, key): return t[key] and remove it')
M.docTy(M.trim, [[trim(subj, pat='%s', index=1) -> string
  removes pat from front+back of string]])
M.docTy(M.doc, [==[Document a type.

Example:
  M.myFn = doc[[myFn is awesome!
  It does ... stuff with a and b.
  ]](function(a, b)
    ...
  end)
]==])
M.docTy(M.docTy, [==[
docTy(ty_, doc): Document a type, prefer `doc` instead.

Example:
  docTy(myTy, [[my doc string]])
]==])

M.KEYS_MAX = 64
M.FMT_SAFE = false

M.pntf = M.doc'pntf(...): print(string.format(...))'
  (function(...) print(string.format(...)) end)
M.errorf = M.doc'errorf(...): error(string.format(...))'
  (function(...) error(string.format(...), 2) end)
M.assertf = M.doc'assertf(a, ...): assert with string.format'
  (function(a, ...)
    if not a then error('assertf: '..string.format(...), 2) end
    return a
  end)

local function rawsplit(subj, ctx)
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
M.rawsplit = M.docTy(rawsplit, [[
Implementation of split, can be used directly.

rawsplit(subj, ctx) -> (ctx, splitstr)
  ctx: {pat, index}. rawsplit adds: si=, ei= (see split)

for ctx, line in rawsplit, text, {'\n', 1} do ... end
]])

M.split = M.doc[[
split subj by pattern starting at index.

  split(subj:str, pat="%s+", index=1) -> forexpr

for ctx, line in split(text, '\n') do
  -- ctx.si: start index of line
  -- ctx.ei: end index of line
  -- table.unpack(ctx) -> pat, nextIndex
end
]]
(function(subj, pat, index)
  return rawsplit, subj, {pat or '%s+', index or 1}
end)

-----------------------------
-- Native types: now add your own with addNativeTy!
-- These dictionaries are used for fast conversion
-- of ty(v) (when the result is a string) into the approriate function.
-- Note: native types must have __metatable='mynativetype'
local NATIVE_TY_GET = {
  ['function'] = function(f) return 'function' end,
  ['nil']      = function()  return 'nil'     end,
  boolean      = function()  return 'boolean' end,
  number       = function()  return 'number'  end,
  string       = function()  return 'string'  end,
  table        = function(t) return getmetatable(t) or 'table' end,
  userdata     = function()  return 'userdata' end,
  thread       = function()  return 'thread'   end,
}

local NATIVE_TY_CHECK = {}; for k in pairs(NATIVE_TY_GET) do
  NATIVE_TY_CHECK[k] = M.nativeEq
end; NATIVE_TY_CHECK['nil'] = nil

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

local NATIVE_TY_NAME = {}
for k in pairs(NATIVE_TY_GET) do NATIVE_TY_NAME[k] = k end

M.tostringFmt = function(v, f) add(f, tostring(v)) end
local NATIVE_TY_FMT = {
  boolean=M.tostringFmt, userdata = M.tostringFmt, thread=M.tostringFmt,
  ['nil']=function(n, f)       add(f, 'nil') end,
  number=function(n, f)        add(f, sfmt(f.set.num, n)) end,
  string=function(s, f)
    if f.set.str ~= '%s' then return add(f, sfmt(f.set.str, s)) end
    -- format with newlines. Last line should not have sep'\n'
    local prev; for _, line in rawsplit, s, {'\n', 1} do
      if prev then
        add(f, prev); f:sep'\n'
      end; prev = line
    end; if prev then add(f, prev) end
  end,
  -- Note: ['function'] = fnFmtSafe  (later)
  -- Note: table        = tblFmtSafe (later)
}

function M.simpleDoc(v, fmt, name)
  if name then fmt:fmt(name); add(fmt, ': ') end
  fmt:fmt(type(v))
end
local NATIVE_TY_DOC = {
  ['nil']  = M.simpleDoc, boolean = M.simpleDoc,
  number   = M.simpleDoc, string  = M.simpleDoc,
  userdata = M.simpleDoc, thread  = M.simpleDoc,
  table = function(t, fmt, name)
    if t.__name or t.__tostring then return helpTy(t, fmt, name)
    else
      if name then fmt:fmt(name); add(fmt, ': ') end
      fmt:fmt'table'; fmt:sep'\n'
    end
    return true
  end,
  ['function'] = function(f, fmt, name)
    if name then
      fmt:fmt(name)
      if fmt.level > 1 and M.FN_DOCS[f] then
        fmt:fmt(string.rep(' ', 36 - #name));
        fmt:fmt'(DOC) '
      else fmt:fmt(string.rep(' ', 42 - #name)) end
      add(fmt, ': ')
    end
    add(fmt, 'function ['); fmt:fmt(f); add(fmt, ']')
    if fmt.level > 1 then return end
    local d = M.FN_DOCS[f]; if d then
      fmt:levelEnter''; fmt:fmt(d); fmt:levelLeave''
    else fmt:sep'\n' end
    return true
  end,
}

M.addNativeTy = M.doc[[
Add your own custom native type.

  addNativeTy(ty_, t) override behavior in t, see implementation.]]
(function(ty_, t)
  local name, t = getmetatable(ty_), t or {}
  assert(type(name) == 'string' and #name > 0,
    'native types must have __metatable="nativeTypeName"')
  M.assertf(not NATIVE_TY_GET[name], '%s already exists', name)
  NATIVE_TY_NAME[name]  = name
  NATIVE_TY_GET[name]   = function() return name end
  NATIVE_TY_FMT[name]   = t.fmt  or M.tostringFmt
  NATIVE_TY_CHECK[name] = t.check or M.checkNative
  NATIVE_TY_EQ[name]    = t.eq   or rawequal
  NATIVE_TY_DOC[name]   = t.doc  or M.simpleDoc
end)

M.ty = M.doc[[Get the type of the value.
  table: getmetatable(v) or 'table'
  other: type(v)]]
(function(obj) return NATIVE_TY_GET[type(obj)](obj) end)

M.callable = M.doc[[callable(obj) -> isCallable
Return true if the object is a function or table with metatable.__call
]](function(obj)
  if type(obj) == 'function' then return true end
  local m = getmetatable(obj); return m and rawget(m, '__call')
end)

-- Ultra-simple index function (for methods)
M.indexUnchecked = function(self, k) return getmetatable(self)[k] end

-- Check returns the constrained type or nil if the types don't check.
--
-- Note: the constrained type is only used for generics, which are implemented
--       in the __check method of those types.
M.tyCheck = function(reqTy, giveTy, reqMaybe)
  if (reqMaybe and giveTy == 'nil') then return reqTy end
  if type(reqTy) == 'string' then
    M.assertf(NATIVE_TY_CHECK[reqTy], '%q is not a valid native type', reqTy)
    return NATIVE_TY_CHECK[reqTy](reqTy, giveTy)
  end
  if reqTy == giveTy then return reqTy end
  local reqCheck = reqTy.__check
  if reqCheck then return reqCheck(reqTy, giveTy) end
end

-- Returns true when checked against any type
M.Any = setmetatable(
  {__name='Any', __check=function() return true end},
  {__tostring=function() return 'Any' end})

M._isTyErrMsg = function(ty_)
  local tystr = type(ty_)
  if tystr == 'string' then
    if not NATIVE_TY_GET[ty_] then return sfmt(
      '%q is not a native type', ty_
    )end
  elseif tystr ~= 'table' then return sfmt(
    '%s cannot be used as a type', tystr
  )end
end

M.tyName = M.doc'(ty_) -> string: safely get the name of a type'
(function(ty_) --> string
  local check = M._isTyErrMsg(ty_);
  if check then return sfmt('<!%s!>', check) end
  return NATIVE_TY_NAME[ty_] or ty_.__name or 'table'
end)

M.tyCheckMsg = function(reqTy, giveTy) --> string
   return sfmt("Type error: require=%s given=%s",
     M.tyName(reqTy), M.tyName(giveTy))
end

-----------------------------
-- Equality

M.geteventhandler = function(a, b, event)
  return (getmetatable(a) or {})[event]
      or (getmetatable(b) or {})[event]
end
M.eq = M.doc'use __eq or auto-deep equality'
  (function(a, b) return NATIVE_TY_EQ[type(a)](a, b) end)

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

----------------------------------------------
-- rawTy: create new types

-- __index function for most types
-- Set metatable.__missing to type check on missing keys.
M.indexChecked = function(self, k) --> any
  if type(k) == 'number' then return nil end
  local mt = getmetatable(self)
  local x = mt[k]; if x ~= nil then return x end
  x = mt.__missing
  return x and x(mt, k) or nil
end

M.newindexChecked = function(self, k, v)
  if type(k) == 'number' then rawset(self, k, v); return end
  local mt = getmetatable(self)
  local fields = mt.__fields
  if not fields[k] then M.errorf(
    '%s does not have field %s', M.tyName(mt), k
  )end
  if not M.tyCheck(fields[k], M.ty(v), mt[k] ~= nil or mt.__maybes[k]) then
    M.errorf('[%s.%s] %s', M.tyName(mt), k, M.tyCheckMsg(fields[k], M.ty(v)))
  end
  rawset(self, k, v)
end

-- These are the default constructor functions
M.newUnchecked = function(ty_, t) return setmetatable(t or {}, ty_) end

M.newChecked = function(ty_, t)
  t = t or {}
  local fields, maybes = ty_.__fields, ty_.__maybes
  for field, v in pairs(t) do
    if type(field) == 'number' then goto continue end
    M.assertf(fields[field], 'unknown field: %s', field)
    ::continue::
  end
  for _, field in ipairs(fields) do
    local v = t[field]; local vTy = M.ty(v)
    if not M.tyCheck(fields[field], vTy, ty_[field] ~= nil or maybes[field]) then
      M.errorf('[field:%s] %s', field, M.tyCheckMsg(fields[field], vTy))
    end
  end
  return setmetatable(t, ty_)
end
M.new = M.doc'return this from :new'
  (CHECK and M.newChecked or M.newUnchecked)

-- MyType = rawTy('MyType', {new=function(ty_, t) ... end})
M.rawTy = M.doc'create a raw type. Prefer record'
(function(name, mt)
  mt = mt or {}
  mt.__name  = mt.__name or sfmt("Ty<%s>", name)
  mt.__call  = mt.__call or M.new
  local ty_ = {
    __name=name,
    __index=M.indexUnchecked,
    __fmt=M.tblFmt,
    __tostring=M.fmt,
  }
  return setmetatable(ty_, mt)
end)

----------------------------------------------
-- record: create record types
--
-- The table (type) created by record has the following fields:
--
-- __name: type name
-- __fields: field types AND ordering by name (runtime)
-- __maybes: map of optional fields
--
-- And the following methods:
--   __index:    instance method lookup and (optional) type checking
--   __newindex: (optional) instance set=field type checking
--   __missing:  (optional) instance missing-field type checking

M._recordNew = function(r, fn)
  getmetatable(r).__call = fn
  return r
end

M._recordFieldDoc = function(r, doc)
  local field = r.__fields[#r.__fields]
  assert(field, 'must specify :fdoc after a :field')
  r.__fdocs = r.__fdocs or {}
  r.__fdocs[field] = assert(doc)
  return r
end

-- i.e. record'Name':field('a', 'number')
M._recordField = function(r, name, ty_, default)
  assert(name, 'must provide field name')
  M.assertf(not r.__fields[name], 'field %s already exists', name)
  M.assertf(not r.name, 'Attempted override of method with field: %s', name)
  ty_ = ty_ or M.Any

  r.__fields[name] = ty_; add(r.__fields, name)
  if nil ~= default then
    M.tyCheck(ty_, M.ty(default))
    r[name] = default
  end
  r.__maybes[name] = nil
  return r
end

-- i.e. record'Name':fieldMaybe('a', 'number')
M._recordFieldMaybe = function(r, name, ty_, default)
  assert(default == nil, 'default given for fieldMaybe')
  M._recordField(r, name, ty_)
  r.__maybes[name] = true
  return r
end

-- Used for records and similar for checking missing fields.
M._recordMissing = function(ty_, k)
  if ty_.__maybes and ty_.__maybes[k] then return end
  M.errorf('%s does not have field %s', M.tyName(ty_), k)
end

M.forceCheckRecord = M.doc[[
make a record type-checked even if not isCheck()]]
(function(r)
  r.__index    = M.indexChecked
  r.__newindex = M.newindexChecked
  r.__missing  = M._recordMissing
end)

M.record = M.doc[[create your own record aka struct.

local Point = record'Point'
  :field('x', 'number')
  :field('y', 'number')
  :fieldMaybe('z', 'number') -- can be nil

-- constructor
Point:new(function(ty_, x, y, z)
  return metaty.new(ty_, {x=x, y=y, z=z})
end]]
(function(name, mt)
  mt = mt or {}
  mt.__index    = M.indexUnchecked
  mt.new        = M._recordNew
  mt.field      = M._recordField
  mt.fieldMaybe = M._recordFieldMaybe
  mt.fdoc       = M._recordFieldDoc

  local r = M.rawTy(name, mt)
  r.__fields = {}  -- field types AND ordering
  r.__maybes = {}  -- maybe (optional) fields
  r.__fmt = M._recordFmt
  if CHECK then M.forceCheckRecord(r) end
  return r
end)

-----------------------
-- record2


M.index = function(R, k) -- Note: R is record's metatable
  if type(k) == 'string' and not rawget(R, '__fields')[k] then
    error(R.__name..' does not have field '..k)
  end
end
M.newindex = function(r, k, v)
  if type(k) == 'string' and not M.metaget(r, '__fields')[k] then
    error(r.__name..' does not have field '..k)
  end
  rawset(r, k, v)
end

M.fieldsCheck = function(fields, t)
  local tkey; while true do
    tkey = next(t, tkey); if not tkey then return end
    if type(tkey) == 'string' and not fields[tkey] then
      error('unrecognized field: '..tkey)
    end
  end
end
M.constructChecked = function(T, t)
  M.fieldsCheck(rawget(T, '__fields'), t)
  return setmetatable(t, T)
end
M.constructUnchecked = function(T, t)
  return setmetatable(t, T)
end
M.construct = (CHECK and M.constructChecked) or M.constructUnchecked

local recordInner = function(name, specs)
  -- parse specs
  local fields, fdocs = {}, {}
  for _, spec in ipairs(specs) do
    -- name [type] : some docs, but [type] and ':' are optional.
    local name, tyname, fdoc = spec:match'^([%w_]+)%s*(%b[])%s*:?%s*(.*)$'
    assert(#name > 0, 'empty name')
    add(fields, name); fields[name] = tyname
    if #fdoc > 0 then fdocs[name] = fdoc end
  end

  if next(fdocs) then FIELD_DOC[name] = fdocs end
  local mt = { __name='Ty<'..name..'>' }
  local R = setmetatable({
    __name=name, __fields=fields,
    __tostring=M.fmt, __fmt=M._recordFmt,
    __fields=fields,
  }, mt)
  R.__index = R
  if METATY_CHECK then
    mt.__call = M.constructChecked
    mt.__index   = M.index
    R.__newindex = M.newindex
  else
    mt.__call = M.constructUnchecked
  end
  return R
end
M.record2 = function(name)
  return function(specs) return recordInner(name, specs) end
end

----------------------------------------------
-- Formatting
M.FMT_NEW = M.new -- overrideable

M.FmtSet = M.doc[[Fmt settings]]
(M.record('FmtSet', {
  __call=function(ty_, t)
    t.safe     = t.safe     or M.FMT_SAFE
    t.keysMax  = t.keysMax  or M.KEYS_MAX
    t.itemSep  = t.itemSep  or ((t.pretty and '\n') or ' ')
    t.levelSep = t.levelSep or ((t.pretty and '\n') or '')
    return M.FMT_NEW(ty_, t)
  end
}))

-- Fields with constructor defaults
M.FmtSet
  :field('safe',      'boolean')
  :field('keysMax',   'number'):fdoc'used for display and sorting'
  :field('itemSep',   'string'):fdoc'separator in map'
  :field('levelSep',  'string'):fdoc'separator for new tables'

-- Fields with normal defaults
M.FmtSet
  :field('pretty',  'boolean', false)
  :field('recurse', 'boolean', true)  :fdoc'make recursion safe'
  :field('indent',  'string',  '  ')
  :field('listSep', 'string',  ',')   :fdoc'separator in list'
  :field('tblSep',  'string',  ' :: '):fdoc'separator between list :: map'
  :field('num',     'string',  '%i')  :fdoc'number format'
  :field('str',     'string',  '%q')  :fdoc'stirng format'
  :field('raw',     'boolean', false) :fdoc'ignore __fmt/__tostring'
  :fieldMaybe('tblFmt',  'function')
  :fieldMaybe'data' -- arbitrary data, use carefully!
M.FmtSet.__missing = M._recordMissing

M.DEFAULT_FMT_SET = M.FmtSet{}

M.Fmt = M.doc[[Fmt anything.
  Override __fmt(self, fmt) of your type to customize formatting.
  Use table.insert(fmt, 'whatever') for raw strings or the
  formatting API for other values.
]](M.record'Fmt')
:new(function(ty_, t)
  t.done, t.level = t.done or {}, t.level or 0
  return M.FMT_NEW(ty_, t)
end)
  :field('done', 'table')
  :field('level', 'number', 0)
  :field('set', M.FmtSet, M.DEFAULT_FMT_SET):fdoc'main settings'
  :fieldMaybe'file':fdoc'write directly to a file'

M.Fmt.__len = function(f) return f.file and 0 or rawlen(f) end
M.Fmt.__newindex = function(f, k, v)
  if f.file then
    assert(k == 1, 'filemode must only append strings')
    f.file:write(v)
  else rawset(f, k, v) end
end
M.Fmt.__missing = function(ty_, k)
  if type(k) == 'number' then return nil end
  return M._recordMissing(ty_, k)
end

-----------
-- Fmt Utilities
M.orderedKeys = M.doc[[(t, max) -> keyList
  max (or metaty.KEYS_MAX) specifies the maximum number
  of keys to order.]]
(function(t, max) --> table (ordered list of keys)
  local keys, len, tlen, max = {}, 0, #t, max or M.KEYS_MAX
  for k in pairs(t) do
    if len >= max then break end
    if type(k) ~= 'number' or k > tlen then
      add(keys, k); len = len + 1
    end
  end
  pcall(table.sort, keys)
  return keys
end)

local STR_IS_AMBIGUOUS = {['true']=true, ['false']=true, ['nil']=true}
M.strIsAmbiguous = M.doc'return whether a string needs %q'
(function(s) --> boolean
  return (
    STR_IS_AMBIGUOUS[s]
    or tonumber(s)
    or s:find('[%s.\'"={}%[%]]')
  )
end)

-----------
-- Fmt Native Types

-- return the table id
-- requirement: metatable is nil or is missing __tostring
local function _tblId(t) --> string
  local id = string.gsub(tostring(t), 'table: ', ''); return id
end

M.metaName = function(mt)
  if not mt or type(mt) ~= 'table' then return ''
  else return mt.__name or '?' end
end

M.fnFmtSafe = function(fn, f)
  add(f, 'Fn')
  local dbg = debug.getinfo(fn, 'nS')
  if dbg.name then add(f, sfmt('%q', dbg.name)) end
  add(f, '@'); add(f, dbg.short_src);
  add(f, ':'); add(f, tostring(dbg.linedefined));
end
NATIVE_TY_FMT['function'] = M.fnFmtSafe

M.tblFmtSafe = function(t, f)
  local mt = getmetatable(t);
  if mt == nil then add(f, 'Tbl@'); add(f, _tblId(t))
  elseif mt.__tostring then
    add(f, M.metaName(mt)); add(f, '{...}')
  else
    add(f, M.metaName(mt)); add(f, '@')
    add(f, _tblId(t));
  end
end
NATIVE_TY_FMT.table = M.tblFmtSafe

M.tblToStrSafe = function(t)
  local mt = getmetatable(t);
  if not mt then return sfmt('Tbl@%s', _tblId(t)) end
  if mt.__tostring then return sfmt('%s{...}', M.metaName(mt)) end
  return sfmt('%s@%s', M.metaName(mt), _tblId(t))
end

M.safeToStr = function(v, set) --> string
  local f = M.Fmt{set=set}; NATIVE_TY_FMT[type(v)](v, f)
  return table.concat(f)
end

M.tblFmtKeys = function(t, f, keys)
  assert(type(t) == 'table', type(t))
  local mt, lenI, lenK = getmetatable(t), #t, #keys
  add(f, M.metaName(mt))
  f:levelEnter('{')
  for i=1,lenI do
    f:fmt(t[i])
    if i < lenI then f:sep(f.set.listSep) end
  end
  if lenI > 0 and lenK > 0 then f:sep(f.set.tblSep) end
  for i, k in ipairs(keys) do
    local v = t[k]; if v == nil then -- skip, happens for fields
    elseif type(k) == 'number' and 0<k and k<=lenI then -- already added
    else
      if     type(k) == 'table' then f:fmt(k)
      elseif type(k) == 'string' and not M.strIsAmbiguous(k) then add(f, k)
      else   add(f, '['); add(f, sfmt('%q', k)); add(f, ']') end
      add(f, '='); f:fmt(v)
      if i < lenK then f:sep(f.set.itemSep) end
    end
  end
  if lenK >= f.set.keysMax then add(f, '...'); end
  f:levelLeave('}')
end

M.tblFmt = M.doc'(t, fmt) format as a table'
(function(t, f)
  return M.tblFmtKeys(t, f, M.orderedKeys(t, f.set.keysMax))
end)
M.FmtSet.tblFmt = M.tblFmt

M._recordFmt = function(r, f)
  M.tblFmtKeys(r, f, M.metaget(r, '__fields'))
end

-----------
-- Fmt Methods
M.Fmt.sep = M.doc'handle possible newlines'
(function(f, sep)
  add(f, sep); if sep:find'\n' then
    add(f, string.rep(f.set.indent, f.level))
  end
end)
M.Fmt.levelEnter = function(f, startCh)
  add(f, startCh)
  f.level = f.level + 1
  if f.set.levelSep ~= '' then f:sep(f.set.levelSep) end
end
M.Fmt.levelLeave = function(f, endCh)
  f.level = f.level - 1
  if f.set.levelSep ~= '' then
    f:sep(f.set.levelSep)
    add(f, endCh)
  else add(f, endCh) end
end

-- Note: may be called inside pcall
local function doFmt(f, v, mt)
  assert(type(v) == 'table', type(v))
  if f.set.raw or not mt or mt == 'table' then
    f.set.tblFmt(v, f)
  elseif mt.__fmt               then mt.__fmt(v, f)
  elseif mt.__tostring ~= M.fmt then add(f, tostring(v))
  else f.set.tblFmt(v, f) end
end

M.Fmt.fmt = M.doc'(f, v): Format the value and store the result in `f`'
(function(f, v)
  local ty_ = M.ty(v)
  if type(ty_) == 'string' and ty_ ~= 'table' then
    NATIVE_TY_FMT[ty_](v, f); return f
  end
  assert(type(v) == 'table')
  if not f.set.recurse then
    if f.done[v] then
      add(f, 'RECURSE['); add(f, M.tblToStrSafe(v)); add(f, ']')
      return f
    else f.done[v] = true end
  end
  local mt = getmetatable(v)
  local len, level = #f, f.level
  if f.set.safe then
    local ok, err = pcall(doFmt, f, v, mt)
    if not ok then
      while #f > len do table.remove(f) end
      f.level = level
      add(f, M.safeToStr(v) )
      add(f, '-->!ERROR!['); add(f, M.safeToStr(err));
      add(f, ']');
    end
  else doFmt(f, v, mt) end
  return f
end)

M.fmt = M.doc[[fmt(v, set, file) -> string
  The output is nil if file is specified.
]](function(v, set, file)
  local f = M.Fmt{set=set, file=file}:fmt(v)
  if not file then return table.concat(f) end
end)

M.pntset = function(set, ...)
  local args = {...}
  local f = M.Fmt{set=set, file=io.stdout}
  for i, arg in ipairs(args) do
    if type(arg) == 'table' then f:fmt(arg)
    else io.stdout:write(tostring(arg)) end
    if i < #args then io.stdout:write('\t') end
  end
  io.stdout:write('\n')
  io.stdout:flush()
end

M.pnt = M.doc[[
pnt(...): basically the same as `print` except:

1. it uses fmt to format the arguments
2. it respects io.stdout]]
  (function(...) M.pntset(nil, ...) end)
M.ppnt = M.doc'pnt but pretty'
  (function(...) M.pntset(M.FmtSet{pretty=true}, ...) end)

-- Cleanup Fmt objects (note: normal defaults were nil)
M.FmtSet.__fmt = M.tblFmt
M.FmtSet.__tostring = M.fmt
M.Fmt.__fmt = nil
M.Fmt.__tostring = function() return 'Fmt{}' end

M.want = M.doc'Alternative to "require" when the module is optional'
(function(mod)
  local ok, mod = pcall(function() return require(mod) end)
  if ok then return mod else return nil, mod end
end)

function M.helpFields(mt, fmt)
  local fields = mt.__fields
  if not fields then return end
  fmt:levelEnter'Fields:'
  for _, field in ipairs(fields) do
    local ty_, maybe = fields[field], mt.__maybes[field]
    fmt:fmt(field); fmt:fmt' ['; fmt:fmt(ty_)
    if maybe then fmt:fmt' default=nil'
    elseif mt[field] then fmt:fmt' default='; fmt:fmt(mt[field]) end
    fmt:fmt']'
    local d = mt.__fdocs; if d and d[field] then
      add(fmt, ': '); fmt:fmt(d[field])
    end
    fmt:sep'\n'
  end
  fmt:levelLeave''
end

local function _members(fmt, name, mt, keys, fields, onlyTy, notTy)
  fmt:levelEnter(name)
  for _, k in ipairs(keys) do
    if fields and fields[k] then goto continue end -- default field
    local v = mt[k]
    if onlyTy and type(v) ~= onlyTy then goto continue end
    if notTy  and type(v) == notTy  then goto continue end
    if not NATIVE_TY_DOC[type(v)](v, fmt, k) then
      fmt:sep'\n'
    end
    ::continue::
  end
  fmt:levelLeave''
end

function M.helpMembers(mt, fmt)
  local fields = mt.__fields
  local keys, mmt = M.orderedKeys(mt, 1024), getmetatable(mt)
  if mmt then
    fmt:fmt('metatable='); fmt:fmt(mmt) fmt:sep'\n'; fmt:sep'\n'
  end
  _members(fmt, 'Members', mt, keys, fields, nil, 'function')
  _members(fmt, 'Methods', mt, keys, fields, 'function')
end

local function helpTy(mt, fmt, name)
  local mmt = getmetatable(mt); if mmt and NATIVE_TY_DOC[mmt] then
    return fmt:fmt(NATIVE_TY_DOC[mmt])
  end
  local ty_ = mt.__name or tostring(mt); local nlen = 2 + #ty_
  if name then fmt:fmt(name); add(fmt, ' ');   nlen = 1 + #name; end
  if fmt.level > 1 and mt.__doc then
    fmt:fmt(string.rep(' ', 36 - nlen))
    fmt:fmt'(DOC) ';
  else fmt:fmt(string.rep(' ', 42 - nlen)) end
  fmt:fmt'['; fmt:fmt(ty_) fmt:fmt']'
  if fmt.level > 1 then return end
  if mt.__doc then
    fmt:fmt': '; fmt:fmt(mt.__doc); fmt:sep'\n';
  end
  fmt:levelEnter''
  M.helpFields(mt, fmt); M.helpMembers(mt, fmt)
  fmt:levelLeave''
end

function M.helpFmter()
  return M.Fmt{set=M.FmtSet{
    pretty=true, str='%s'
  }}
end

M.help = M.doc'(v) -> string: Get help'
(function(v)
  local name; if type(v) == 'string' then
    name, v = v, require(v)
  end
  local f = M.helpFmter()
  if type(v) == 'table' then helpTy(v, f, name)
  else NATIVE_TY_DOC[type(v)](v, f) end
  return M.trim(table.concat(f))
end)


return M
