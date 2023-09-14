-- metaty: simple but effective Lua type system using metatable
--
-- See README.md for documentation.

local CHECK = _G['METATY_CHECK'] or false -- private
local M = {}
M.getCheck = function() return CHECK end

-- Utilities / aliases
local add, sfmt = table.insert, string.format
local function identity(v) return v end
local function nativeEq(a, b) return a == b end
local function getOrEmpty(t, k)
  local o = t[k]; if not o then o = {}; t[k] = o end
  return o
end

local function copy(t, update)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  setmetatable(out, getmetatable(t))
  if update then
    for k, v in pairs(update) do out[k] = v end
  end
  return out
end
local function deepcopy(t)
  local out = {}; for k, v in pairs(t) do
    if 'table' == type(v) then v = deepcopy(v) end
    out[k] = v
  end
  return setmetatable(out, getmetatable(t))
end


M.KEYS_MAX = 64
M.FMT_SAFE = false
M.FNS = {}      -- function types (registered)
M.FNS_UNCHECKED = {} -- functions w/out type check wrapper
M.FNS_INFO = {} -- function debug info

M.errorf  = function(...) error(string.format(...)) end
M.assertf = function(a, ...)
  if not a then error('assertf: '..string.format(...)) end
  return a
end

M.defaultNativeCheck = function(_chk, anchor, reqTy, giveTy)
  return reqTy == giveTy
end

local NATIVE_TY_GET = {
  ['function'] = function(f) return M.FNS[f] or 'function' end,
  ['nil']      = function()  return 'nil'     end,
  boolean      = function()  return 'boolean' end,
  number       = function()  return 'number'  end,
  string       = function()  return 'string'  end,
  table        = function(t) return getmetatable(t) or 'table' end,
}

local NATIVE_TY_CHECK = {}; for k in pairs(NATIVE_TY_GET) do
  NATIVE_TY_CHECK[k] = M.defaultNativeCheck
end; NATIVE_TY_CHECK['nil'] = nil

local NATIVE_TY_NAME = {}
for k in pairs(NATIVE_TY_GET) do NATIVE_TY_NAME[k] = k end

-- Use to add/override a native type
M.setNativeTy = function(name, getTy, check)
  NATIVE_TY_NAME[name]  = name
  NATIVE_TY_GET[name]   = getTy
  NATIVE_TY_CHECK[name] = check
end

-- Return type which is the metatable (if it exists) or raw type() string.
M.ty = function(obj) return NATIVE_TY_GET[type(obj)](obj) end

-- Ultra-simple index function
M.indexUnchecked = function(self, k) return getmetatable(self)[k] end

M.Checker = setmetatable({
  __name='Checker',
  __index=M.indexUnchecked,
}, {
  __name='Ty<Checker>',
  -- Checker{} constructor
  __call=function(ty_, t)
    t.gen = t.gen or {}
    return setmetatable(t, ty_)
  end,
})


-- Check returns the constrained type or nil if the types don't check.
--
-- Note: the constrained type is only used for generics, which are implemented
--       in the __check method of those types.
M.Checker.check = function(self, anchor, reqTy, giveTy, reqMaybe)
  if (reqMaybe and giveTy == 'nil') then return reqTy end
  if type(reqTy) == 'string' then
    M.assertf(NATIVE_TY_CHECK[reqTy], '%s is not a valid native type', reqTy)
    return NATIVE_TY_CHECK[reqTy](self, anchor, reqTy, giveTy)
  end
  if M.ty(reqTy) == M.g then
    reqTy = self:resolveGenVar(anchor, reqTy.var, giveTy)
  end
  if reqTy == giveTy then return reqTy end
  local reqCheck = rawget(reqTy, '__check')
  if reqCheck then return reqCheck(self, anchor, reqTy, giveTy) end
end

-- Resolve the Generic Variable's from anchor type's genvars and
-- update chk.gen
M.Checker.resolveGenVar = function(chk, aTy, vname, useTy) -- aTy=anchorTy
  if not useTy or not M.isConcreteTy(useTy) then
    M.assertf(aTy, 'no anchor provided for generic <%s>', vname)
    local gv = M.assertf(aTy.__genvars,
      'Cannot resolve %s on non-generic %s', vname, aTy)
    useTy = M.assertf(gv[vname],
      '(anchor) %s does not have generic var %s', aTy, vname)
  end
  local cur = chk.gen[vname]; if cur then
    useTy = M.assertf(chk:check(cty, cur, useTy)
      "%s already chosen as %s, does not type check with %s", vname, cur, useTy)
  end
  chk.gen[vname] = useTy
  return useTy
end

M.tyCheck = function(reqTy, giveTy, reqMaybe) --> bool
  return M.Checker{}:check(nil, reqTy, giveTy, reqMaybe)
end

-- Returns true when checked against any type
M.Any = setmetatable(
  {__name='Any', __check=function() return true end},
  {__tostring=function() return 'Any' end})

M.isTyErrMsg = function(ty_)
  local tystr = type(ty_)
  if tystr == 'string' then
    if not NATIVE_TY_GET[ty_] then return sfmt(
      '%q is not a native type', ty_
    )end
  elseif tystr ~= 'table' then return sfmt(
    '%s cannot be used as a type', tystr
  )end
end

-- Safely get the name of type
M.tyName = function(ty_) --> string
  local check = M.isTyErrMsg(ty_);
  if check then return sfmt('<!%s!>', check) end
  return NATIVE_TY_NAME[ty_] or rawget(ty_, '__name') or 'table'
end

M.tyCheckMsg = function(reqTy, giveTy) --> string
   return sfmt("Type error: require=%s given=%s",
     M.tyName(reqTy), M.tyName(giveTy))
end
M.tysCheck = function(chk, anchor, values, tys, maybes, context)
  local len; if maybes then len = #maybes
  else
    len = #values
    if len ~= #tys then errorf(
      "ty len differs: expected=%s, given=%s", #tys, len
    )end
  end
  maybes = maybes or {}
  for i=1,len do
    local v = values[i]
    if not chk:check(anchor, tys[i], ty(v), maybes[i]) then
      M.errorf('[%s] %s%s', i, M.tyCheckMsg(tys[i], ty(v)), context)
    end
  end
end

-----------------------------
-- Equality

M.geteventhandler = function(a, b, event)
  return (getmetatable(a) or {})[event]
      or (getmetatable(b) or {})[event]
end

local EQ = {
  number = nativeEq, boolean = nativeEq, string = nativeEq,
  ['nil'] = nativeEq, ['function'] = nativeEq,
  ['table'] = function(a, b)
    if M.geteventhandler(a, b, '__eq') then return a == b end
    if a == b                          then return true   end
    return M.eqDeep(a, b)
  end,
}
M.eq = function(a, b) return EQ[type(a)](a, b) end

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
  local mt = getmetatable(self)
  local x = rawget(mt, k); if x then return x end
  x = rawget(mt, '__missing')
  return x and x(mt, k) or nil
end

M.newindexChecked = function(self, k, v)
  local mt = getmetatable(self)
  local tys = rawget(mt, '__tys')
  if not tys[k] then errorf(
    '%s does not have field %s', M.tyName(mt), k
  )end
  if not M.tyCheck(tys[k], M.ty(v), rawget(mt, '__maybes')[k]) then
    errorf('%s: %s', M.tyName(mt), M.tyCheckMsg(tys[k], ty(v)))
  end
  rawset(self, k, v)
end

-- These are the default constructor functions
M.newUnchecked = function(ty_, t) return setmetatable(t or {}, ty_) end

M.newChecked   = function(ty_, t)
  t = t or {}
  local chk = M.Checker{}
  local tys, maybes = ty_.__tys, ty_.__maybes
  for field, v in pairs(t) do
    M.assertf(tys[field], 'unknown field: %s', field)
    local vTy = M.ty(v)
    assert(M.isConcreteTy(vTy), '[%s] is generic: %s', field, vTy)
    print('! newChecked:', field, tys[field], vTy)
    if not chk:check(vTy, tys[field], vTy, maybes[field]) then
      print('! ... after check:', field, tys[field], vTy)
      M.errorf('[%s] %s', field, M.tyCheckMsg(tys[field], vTy))
    end
  end
  return setmetatable(t, ty_)
end
M.new = CHECK and M.newChecked or M.newUnchecked

-- MyType = rawTy('MyType', {new=function(ty_, t) ... end})
M.rawTy = function(name, mt)
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
end

----------------------------------------------
-- Generic Types
--
-- The user should use generics like:
--   local GenFn = Fn{g'A', g'A'}:out{g'A'}
--   local GenType = record'GenType'
--     :generic'A' :generic('B', Table{I='A'})
--     :field(a, g'A')
--
--   GenType.myMethod = Method{g'A'}:out{g'B'}
--   :apply(function(self, a) ... end)
--
--   local TypeNum = GenType{A='number'}
--   local n = TypeNum{a=7}
--   ... call functions on n and access n.a normally

local GENERIC_VARS = {} -- Cached genvar singletons
local GENERICS = {}     -- Trie of generic type singletons

-- Note: Do NOT create these directly, use the `g()` function.
M.g = setmetatable({
  __name='GenVar', 
  __index=function(v, k)
      if k == 'var' then return v['#var__doNotSet'] end
      error('GenVar does not have field: '..k)
    end,
}, {
  __name='Ty<GenVar>',
  __call=function(ty_, var)
    assert(ty_ == M.g)
    local v = GENERIC_VARS[var]
    if not v then
      v = {__name='<'..var..'>', ['#var__doNotSet']=var}
      GENERIC_VARS[var] = setmetatable(v, M.g)
    end
    return v
  end,
})

M.isConcreteTy = function(ty_)
  return (
    type(ty_) == 'string'
    or (type(ty_) == 'table'
        and rawget(ty_, '__kind') == 'concrete'))
end

-- Prefer to use nxt if it is concrete
M.chooseAnchor = function(prev, nxt)
  return isConcreteTy(nxt) and nxt or prev
end


-- Do record type checking and return new constraints
-- For example: recordCheck(nil, Table{I=g'I'}, Table{I='number'})
M.recordCheck = function(chk, anchor, reqTy, giveTy)
  pnt('!! recordCheck', tostring(anchor), reqTy, giveTy)
  -- handled in Checker.check
  assert(type(reqTy) == 'table'); assert(type(giveTy) == 'table')
  assert(reqTy ~= giveTy)

  if reqTy.__kind == 'generic' then
    anchor = M.chooseAnchor(c, reqTy)
    assertf(anchor, 'No anchor type: require=%s given=%s', reqTy, giveTy)
    for vname in pairs(reqTy.__genvars) do
      local rTy = chk:resolveGenVar(anchor, vname)
      local gTy = giveTy.__genvars[vname]
      pnt(sfmt('!! genvar=%s: ', vname), M.tyCheckMsg(rTy, gTy))
      if not chk:check(anchor, rTy, gTy) then return nil end
    end
    return reqTy
  end
  -- TODO: parents check
  return nil
end

----------------------
-- Create New Generic Type

-- Create a new type with the variables substituted from varMap
M.substituteVars = function(genTy, varMap, new)
  assert(genTy.__kind == 'generic', 'Cannot substitute non-generic')
  local t = copy(genTy)
  local mt = copy(getmetatable(genTy))
  setmetatable(t, mt)
  t.__name = t.__name..M.fmt(varMap)
  t.__kind = 'concrete'
  mt.__name = 'Ty<'..t.__name..'>'
  mt.__call = assert(t.__gencall)
  t.__gencall = nil
  t.__fromgen = genTy
  -- TODO: check constraints
  for k in pairs(t.__genvars) do t.__genvars[k] = varMap[k] or M.Any end
  return t
end

-- new (aka __call) for Generic types
-- i.e. Table{I='number'} calls newGeneric
-- Attempts to lookup the (existing) generic type,
-- else creates a new one
M.newGeneric = function(genTy, varMap, newGenerated)
  -- GENERICS is a trie that for record'MyGen':generic'A':generic'B'
  -- might look like:
  -- {MyGen={
  --   --<A>   <B>      or alternate        <B>
  --   number={number=MyGen{number,number}, string=MyGen{number,string}},
  --   --<A>    <B>
  --   string={ ... },
  --   Any={...},
  -- }}
  local c = getOrEmpty(GENERICS, genTy)
  local vars = genTy.__genvars
  local gen
  for i, vname in ipairs(vars) do
    vTy = varMap[vname] or M.Any
    if i < #vars then c = getOrEmpty(c, vTy)
    else -- last item: either get or create substituted type
      gen = c[vTy]; if not gen then
        gen = substituteVars(genTy, varMap, newGenerated)
        c[vTy] = gen
      end
    end
  end
  return assert(gen)
end

----------------------------------------------
-- record: create record types
--
-- The table (type) created by record has the following fields:
--
-- __name: type name
-- __kind: concrete or generic
-- __tys:  field types AND ordering (by name)
-- __maybes: map of optional fields
-- __genvars: (optional) generic constraints AND ordering (by name)
-- __gencall: (optional) holds the 'new' method of the concrete type.
-- __fromgen: (optional) holds the generic type of a concrete type
--
-- And the following methods:
--   new:        set constructor (__call on metatable)
--   generic:    generic variable (w/optional constraint)
--   field:      add field to the record
--   fieldMaybe: add optional-field to the record
--   __index:    instance method lookup and (optional) type checking
--   __newindex: (optional) instance set=field type checking
--   __missing:  (optional) instance missing-field type checking

M.recordNew = function(r, fn)
  assert(r.__kind == 'concrete', 'Must set new before generic')
  getmetatable(r).__call = fn
  return r
end

-- i.e. record'Name':generic('A', 'number')
M.recordGeneric = function(r, name, constraintTy)
  M.assertf(#r.__tys == 0, 'Must specify generics before any fields')
  r.__kind = 'generic'
  r.__genvars = r.__genvars or {}
  assertf(not r.__genvars[name], 'attempt to overide generic: %s', name)
  add(r.__genvars, name); r.__genvars[name] = constraintTy or M.Any

  local mt = getmetatable(r)
  if not r.__gencall then r.__gencall = mt.__call end
  mt.__call = M.newGeneric
  return r
end

-- i.e. record'Name':field('a', 'number')
M.recordField = function(r, name, ty_, default)
  assert(name, 'must provide field name')
  M.assertf(not r.__tys[name], 'Attempted override of field: %s', name)
  M.assertf(not r.name, 'Attempted override of method with field: %s', name)
  ty_ = ty_ or M.Any

  r.__tys[name] = ty_; add(r.__tys, name)
  if nil ~= default then
    M.tyCheck(ty_, M.ty(default))
    r[name] = default
  end
  r.__maybes[name] = nil
  return r
end

-- i.e. record'Name':fieldMaybe('a', 'number')
M.recordFieldMaybe = function(r, name, ty_, default)
  assert(default == nil, 'default given for fieldMaybe')
  M.recordField(r, name, ty_)
  r.__maybes[name] = true
  return r
end

-- Used for records and similar for checking missing fields.
M.fieldMissing = function(ty_, k)
  local maybes = rawget(ty_, '__maybes')
  if maybes and maybes[k] then return end
  M.errorf('%s does not have field %s', M.tyName(ty_), k)
end

M.forceCheckRecord = function(r)
  r.__index    = M.indexChecked
  r.__newindex = M.newindexChecked
  r.__missing  = M.fieldMissing
end

M.record = function(name, mt)
  mt = mt or {}
  mt.__index    = M.indexUnchecked
  mt.new        = M.recordNew
  mt.generic    = M.recordGeneric
  mt.field      = M.recordField
  mt.fieldMaybe = M.recordFieldMaybe

  local r = M.rawTy(name, mt)
  r.__kind = 'concrete'
  r.__tys = {}     -- field types
  r.__maybes = {}  -- maybe (optional) fields
  r.__check = M.recordCheck
  if CHECK then M.forceCheckRecord(r) end
  return r
end

----------------------------------------------
-- Fn: register function types

M.assertIsTys = function(tys)
  for i, ty_ in ipairs(tys) do
    local err = M.isTyErrMsg(ty_)
    M.assertf(not err, '[arg %s] %s', i, err)
  end
  return tys
end

M.FnInfo = M.record('FnInfo')
  :field('debug', M.Any)
  :field('name', 'string', '')

M.Fn = M.record('Fn', {
  __call=function(ty_, inputs)
    assert(M.ty(inputs) == 'table', 'inputs must be a raw table')
    local t = {
      inputs=M.assertIsTys(inputs),
      outputs={},
    }
    return M.newChecked(ty_, t)
  end
})
  :field('inputs',  'table') :field('outputs', 'table')
  :fieldMaybe('iMaybes', 'table')
  :fieldMaybe('oMaybes', 'table')

M.forceCheckRecord(M.Fn)

M.Fn.inpMaybe = function(self, m)
  M.assertf(M.ty(m) == 'table', 'inpMaybe must be list of booleans')
  M.assertf(#m == #self.inputs, 'inpMaybe len must be same as inp')
  self.iMaybes = m
  return self
end

M.Fn.out = function(self, outputs)
  assert(M.ty(outputs) == 'table', 'outputs must be a raw table')
  self.outputs = M.assertIsTys(outputs)
  return self
end
M.Fn.outMaybe = function(self, m)
  M.assertf(M.ty(m) == 'table', 'outMaybe must be list of booleans')
  M.assertf(#m == #self.outputs, 'outMaybe len must be same as out')
  self.oMaybes = m
  return self
end

M.Fn.apply = function(self, fn, name)
  if M.FNS[fn] then errorf('fn already applied: %s', fmt(fn)) end
  local dbg = debug.getinfo(fn, 'nS')
  M.FNS_INFO[fn] = M.FnInfo{debug=dbg, name=name or dbg.name}
  M.FNS[fn] = self
  local unchecked = fn
  if CHECK then
    local chk = Checker{}
    local inner = fn
    fn = function(...)
      M.tysCheck(chk, nil, {...}, self.inputs, self.iMaybes, ' (fn inp)')
      local o = {inner(...)}
      M.tysCheck(chk, nil, o, self.outputs, self.oMaybes, ' (fn out)')
      return table.unpack(o)
    end
    M.FNS_INFO[fn] = FnInfo{debug=dbg, name=name or dbg.name}
    M.FNS[fn] = self
    M.FNS_UNCHECKED[fn] = unchecked
  end
  return fn
end

----------------------------------------------
-- Formatting
M.FMT_NEW = M.new -- overrideable

M.FmtSet = M.record('FmtSet', {
  __call=function(ty_, t)
    t.safe     = t.safe     or M.FMT_SAFE
    t.keysMax  = t.keysMax  or M.KEYS_MAX
    t.itemSep  = t.itemSep  or ((t.pretty and '\n') or ' ')
    t.levelSep = t.levelSep or ((t.pretty and '\n') or '')
    return M.FMT_NEW(ty_, t)
  end
})

-- Fields with constructor defaults
M.FmtSet
  :field('safe',      'boolean')
  :field('keysMax',   'number')
  :field('itemSep',   'string')
  :field('levelSep',  'string')

-- Fields with normal defaults
M.FmtSet
  :field('pretty',    'boolean', false)
  :field('recurse', 'boolean', true)
  :field('indent',  'string',  '  ')
  :field('listSep', 'string',  ',')
  :field('tblSep',  'string',  ' :: ')
  :field('num',     'string',  '%i')
M.FmtSet.__missing = M.fieldMissing

M.DEFAULT_FMT_SET = M.FmtSet{}

M.Fmt = M.record('Fmt', {
  __call=function(ty_, t)
    t.done = t.done or {}
    t.level = t.level or 0
    return M.FMT_NEW(ty_, t)
  end})
  :field('done', 'table')
  :field('level', 'number', 0)
  :field('set', M.FmtSet, M.DEFAULT_FMT_SET)
M.Fmt.__newindex = nil
M.Fmt.__missing = function(ty_, k)
  if type(k) == 'number' then return nil end
  return M.fieldMissing(ty_, k)
end

-----------
-- Fmt Utilities

M.orderedKeys = function(t, max) --> table (ordered list of keys)
  local keys, len, max = {}, 0, max or M.KEYS_MAX
  for k in pairs(t) do
    if len >= max then break end
    len = len + 1
    add(keys, k)
  end
  pcall(function() table.sort(keys) end)
  return keys
end

local STR_IS_AMBIGUOUS = {['true']=true, ['false']=true, ['nil']=true}
M.strIsAmbiguous = function(s) --> boolean
  return (
    STR_IS_AMBIGUOUS[s]
    or tonumber(s)
    or s:find('[%s\'"={}%[%]]')
  )
end

-----------
-- Fmt Native Types

-- return the table id
-- requirement: metatable is nil or is missing __tostring
M.tblIdUnsafe = function(t) --> string
  local id = string.gsub(tostring(t), 'table: ', ''); return id
end

M.metaName = function(mt)
  if mt then return mt.__name or '?'
  else return '' end
end

-- Formatting function type with arguments
M.tyFmtSafe = function(f, ty_, maybe)
  if maybe then add(f, '?') end
  local tyTy = ty(ty_)
  if tyTy == Fn then M.fnTyFmtSafe(tyTy, f)
  elseif tyTy == 'string' then add(f, ty_) -- native
  else add(f, ty_.__name) end
end
M.fmtTysSafe = function(f, tys, maybes)
  maybes = maybes or {}
  for i, ty_ in ipairs(tys) do
    M.tyFmtSafe(f, ty_, maybes[i])
  end
end
M.fnTyFmtSafe = function(fnTy, f)
  add(f, 'Fn['); M.tysFmtSafe(f, self.inputs,  self.iMaybes)
  add(f, '->');  M.tysFmtSafe(f, self.outputs, self.oMaybes)
  add(f, ']');
end

M.fnFmtSafe = function(fn, f)
  local fnTy, dbg, name = ty(fn), nil, nil
  if fnTy == 'function' then
    add(f, 'Fn')
    dbg = debug.getinfo(fn, 'nS'); name = dbg.name
  else assert(ty(fnTy) == Fn)
    M.fnTyFmtSafe(fnTy, f)
    local info = assert(M.FNS_INFO[fn])
    dbg = info.debug; name = info.name
  end
  if name then add(f, sfmt('%q', name)) end
  add(f, '@'); add(f, dbg.short_src);
  add(f, ':'); add(f, tostring(dbg.linedefined));
end
M.Fn.__fmt = M.fnFmtSafe

M.tblFmtSafe = function(t, f)
  local mt = getmetatable(t);
  if not mt then
    add(f, 'Tbl@'); add(f, M.tblIdUnsafe(t))
  elseif mt.__tostring then
    add(f, M.metaName(mt)); add(f, '{...}')
  else
    add(f, M.metaName(mt)); add(f, '@')
    add(f, M.tblIdUnsafe(t));
  end
end
M.tblToStrSafe = function(t)
  local mt = getmetatable(t);
  if not mt then return sfmt('Tbl@%s', M.tblIdUnsafe(t)) end
  if mt.__tostring then return sfmt('%s{...}', M.metaName(mt)) end
  return sfmt('%s@%s', M.metaName(mt), M.tblIdUnsafe(t))
end

local SAFE = {
  ['nil']=function(n, f)       add(f, 'nil') end,
  ['function']=function(fn, f) M.fnFmtSafe(fn, f) end,
  boolean=function(v, f)       add(f, tostring(v)) end,
  number=function(n, f)        add(f, sfmt(f.set.num, n)) end,
  string=function(s, f)
    if M.strIsAmbiguous(s) then add(f, sfmt('%q', s))
    else                        add(f, s) end
  end,
  table=M.tblFmtSafe,
}

M.safeToStr = function(v, set) --> string
  local f = Fmt{set=set}; SAFE[type(v)](v, f)
  return f:toStr()
end

M.tblFmt = function(t, f)
  assert(type(t) == 'table', type(t))
  local mt = getmetatable(t)
  add(f, M.metaName(mt))
  local lenI = #t
  f:levelEnter('{')
  for i=1,lenI do
    f:fmt(t[i])
    if i < lenI then f:sep(f.set.listSep) end
  end

  local keys = M.orderedKeys(t, f.set.keysMax)
  local lenK = #keys
  if lenI > 0 and lenK - lenI > 0 then f:sep(f.set.tblSep) end
  for i, k in ipairs(keys) do
    if type(k) == 'number' and 0<k and k<=lenI then -- already added
    else
      f:fmt(k);    add(f, '=')
      f:fmt(t[k]);
      if i < lenK then f:sep(f.set.itemSep) end
    end
  end
  if lenK >= f.set.keysMax then add(f, '...'); end
  f:levelLeave('}')
end

-----------
-- Fmt Methods
M.Fmt.sep = function(f, sep)
  add(f, sep); if sep == '\n' then
    add(f, string.rep(f.set.indent, f.level))
  end
end
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

-- Format the value and store the result in `f`
M.Fmt.fmt = function(f, v)
  local tystr = type(v)
  if tystr ~= 'table' then
    SAFE[tystr](v, f)
    return f
  end
  if not f.set.recurse then
    if f.done[v] then
      add(f, 'RECURSE['); add(f, M.tblToStrSafe(v)); add(f, ']')
      return f
    else f.done[v] = true end
  end
  local mt = getmetatable(v)
  local len, level = #f, f.level
  local doFmt = function()
    if not mt then M.tblFmt(v, f)
    elseif rawget(mt, '__fmt') then mt.__fmt(v, f)
    elseif rawget(mt, '__tostring') ~= M.fmt then
      add(f, tostring(v))
    else M.tblFmt(v, f) end
  end
  if f.set.safe then
    local ok, err = pcall(doFmt)
    if not ok then
      while #f > len do table.remove(f) end
      f.level = level
      add(f, M.safeToStr(v) )
      add(f, '-->!ERROR!['); add(f, M.safeToStr(err));
      add(f, ']');
    end
  else doFmt() end
  return f
end

M.Fmt.toStr = function(f) return table.concat(f, '') end
M.Fmt.write = function(f, fd)
  for _, s in ipairs(f) do fd:write(s) end
end
M.Fmt.pnt = function(f)
  f:write(io.stdout)
  io.stdout:write('\n')
  io.stdout:flush()
end

M.fmt = function(v, set)
  return M.Fmt{set=set}:fmt(v):toStr()
end

-- This is basically the same as `print` except:
--
-- 1. it uses fmt to format the arguments
-- 2. it respects io.stdout
M.pnt = function(...)
  local args = {...}
  for i, arg in ipairs(args) do
    if type(arg) ~= 'table' then
      io.stdout:write(tostring(arg))
    else
      io.stdout:write(M.fmt(arg))
    end
    if i < #args then io.stdout:write('\t') end
  end
  io.stdout:write('\n')
  io.stdout:flush()
end


-----------
-- Asserting

M.lines = function(text)
  local out = {}; for l in text:gmatch'[^\n]*' do add(out, l) end
  return out
end

M.explode = function(s)
  local t = {}; for ch in s:gmatch('.') do add(t, ch) end
  return t
end

M.diffCol = function(sL, sR)
  local i, sL, sR = 1, M.explode(sL), M.explode(sR)
  while i <= #sL and i <= #sR do
    if sL[i] ~= sR[i] then return i end
    i = i + 1
  end
  if #sL < #sR then return #sL + 1 end
  if #sR < #sL then return #sR + 1 end
  return nil
end

M.diffLineCol = function(linesL, linesR)
  local i = 1
  while i <= #linesL and i <= #linesR do
    local lL, lR = linesL[i], linesR[i]
    if lL ~= lR then
      return i, assert(M.diffCol(lL, lR))
    end
    i = i + 1
  end
  if #linesL < #linesR then return #linesL + 1, 1 end
  if #linesR < #linesL then return #linesR + 1, 1 end
  return nil
end

M.diffFmt = function(f, sE, sR)
  local linesE = M.lines(sE)
  local linesR = M.lines(sR)
  local l, c = M.diffLineCol(linesE, linesR)
  print('# E:', sE)
  print('# R:', sR)
  M.assertf(l and c, '%s, %s\n', l, c)
  add(f, sfmt("! Difference line=%q (", l))
  add(f, sfmt('lines[%q|%q]', #linesE, #linesR))
  add(f, sfmt(' strlen[%q|%q])\n', #sE, #sR))
  add(f, '! EXPECT: '); add(f, linesE[l]); add(f, '\n')
  add(f, '! RESULT: '); add(f, linesR[l]); add(f, '\n')
  add(f, string.rep(' ', c - 1 + 10))
  add(f, sfmt('^ (column %q)\n', c))
  add(f, '! END DIFF\n')
end

M.assertEq = function(expect, result, pretty)
  if M.eq(expect, result) then return end
  local f = M.Fmt{
    set=M.FmtSet{
      pretty=((pretty == nil) and true) or pretty,
    },
  }
  add(f, "! Values not equal:")
  add(f, "\n! EXPECT: "); f:fmt(expect)
  add(f, "\n! RESULT: "); f:fmt(result)
  add(f, '\n')
  if type(expect) == 'string' and type(result) == 'string' then
    M.diffFmt(f, expect, result)
  end
  error(f:toStr())
end

M.assertErrorPat = function(errPat, fn, plain)
  local ok, err = pcall(fn)
  if ok then M.errorf(
    '! No error received, expected: %q', errPat
  )end
  if not err:find(errPat, 1, plain) then M.errorf(
    '! Expected error %q but got %q', errPat, err
  )end
end

M.assertMatch = function(expectPat, result)
  if not result:match(expectPat) then
    M.errorf('Does not match pattern:\nPattern: %q\n Result:  %s',
           expectPat, result)
  end
end

M.test = function(name, fn) print('# Test', name) fn() end

-- Globally require a module. ONLY FOR TESTS.
M.grequire = function(mod)
  if type(mod) == 'string' then mod = require(mod) end
  for k, v in pairs(mod) do
    M.assertf(not _G[k], '%s already global', k); _G[k] = v
  end
  return mod
end

-- Cleanup Fmt objects (note: normal defaults were nil)
M.FmtSet.__fmt = M.tblFmt
M.FmtSet.__tostring = M.fmt
M.Fmt.__fmt = nil
M.Fmt.__tostring = function() return 'Fmt{}' end

return M
