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

-- Check returns the constrained type or nil if the types don't check.
--
-- Note: the constrained type is only used for generics, which are implemented
--       in the __check method of those types.
M.tyCheck = function(reqTy, giveTy, reqMaybe)
  if (reqMaybe and giveTy == 'nil') then return reqTy end
  if type(reqTy) == 'string' then
    M.assertf(NATIVE_TY_CHECK[reqTy], '%s is not a valid native type', reqTy)
    return NATIVE_TY_CHECK[reqTy](reqTy, giveTy)
  end
  if reqTy == giveTy then return reqTy end
  local reqCheck = rawget(reqTy, '__check')
  if reqCheck then return reqCheck(reqTy, giveTy) end
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
  local fields = rawget(mt, '__fields')
  if not fields[k] then errorf(
    '%s does not have field %s', M.tyName(mt), k
  )end
  if not M.tyCheck(fields[k], M.ty(v), rawget(mt, '__maybes')[k]) then
    errorf('%s: %s', M.tyName(mt), M.tyCheckMsg(fields[k], ty(v)))
  end
  rawset(self, k, v)
end

-- These are the default constructor functions
M.newUnchecked = function(ty_, t) return setmetatable(t or {}, ty_) end

M.newChecked   = function(ty_, t)
  t = t or {}
  local fields, maybes = ty_.__fields, ty_.__maybes
  for field, v in pairs(t) do
    M.assertf(fields[field], 'unknown field: %s', field)
    local vTy = M.ty(v)
    if not M.tyCheck(vTy, fields[field], maybes[field]) then
      M.errorf('[%s] %s', field, M.tyCheckMsg(fields[field], vTy))
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
-- record: create record types
--
-- The table (type) created by record has the following fields:
--
-- __name: type name
-- __fields: field types AND ordering by name (runtime)
-- __maybes: map of optional fields
--
-- And the following methods:
--   new:        function to set constructor (__call on metatable)
--   field:      add field (with runtime-ty and default) to the record
--   fieldMaybe: add optional-field to the record
--   __index:    instance method lookup and (optional) type checking
--   __newindex: (optional) instance set=field type checking
--   __missing:  (optional) instance missing-field type checking

M.recordNew = function(r, fn)
  getmetatable(r).__call = fn
  return r
end

-- i.e. record'Name':field('a', 'number')
M.recordField = function(r, name, ty_, default)
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
M.recordFieldMaybe = function(r, name, ty_, default)
  assert(default == nil, 'default given for fieldMaybe')
  M.recordField(r, name, ty_)
  r.__maybes[name] = true
  return r
end

-- Used for records and similar for checking missing fields.
M.recordMissing = function(ty_, k)
  local maybes = rawget(ty_, '__maybes')
  if maybes and maybes[k] then return end
  M.errorf('%s does not have field %s', M.tyName(ty_), k)
end

M.forceCheckRecord = function(r)
  r.__index    = M.indexChecked
  r.__newindex = M.newindexChecked
  r.__missing  = M.recordMissing
end

M.record = function(name, mt)
  mt = mt or {}
  mt.__index    = M.indexUnchecked
  mt.new        = M.recordNew
  mt.field      = M.recordField
  mt.fieldMaybe = M.recordFieldMaybe

  local r = M.rawTy(name, mt)
  r.__fields = {}  -- field types AND ordering
  r.__maybes = {}  -- maybe (optional) fields
  r.__fmt = M.recordFmt
  if CHECK then M.forceCheckRecord(r) end
  return r
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
M.FmtSet.__missing = M.recordMissing

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
  return M.recordMissing(ty_, k)
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
  if tyTy == 'string' then add(f, ty_) -- native
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
  add(f, 'Fn')
  local dbg = debug.getinfo(fn, 'nS')
  if dbg.name then add(f, sfmt('%q', dbg.name)) end
  add(f, '@'); add(f, dbg.short_src);
  add(f, ':'); add(f, tostring(dbg.linedefined));
end

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

M.tblFmtKeys = function(t, f, keys)
  assert(type(t) == 'table', type(t))
  local mt = getmetatable(t)
  add(f, M.metaName(mt))
  local lenI = #t
  f:levelEnter('{')
  for i=1,lenI do
    f:fmt(t[i])
    if i < lenI then f:sep(f.set.listSep) end
  end
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

M.tblFmt = function(t, f)
  return M.tblFmtKeys(t, f, M.orderedKeys(t, f.set.keysMax))
end

M.recordFmt = function(r, f)
  M.tblFmtKeys(r, f, getmetatable(r).__fields)
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

local function lines(text)
  local out = {}; for l in text:gmatch'[^\n]*' do add(out, l) end
  return out
end

local function explode(s)
  local t = {}; for ch in s:gmatch('.') do add(t, ch) end
  return t
end

local function diffCol(sL, sR)
  local i, sL, sR = 1, explode(sL), M.explode(sR)
  while i <= #sL and i <= #sR do
    if sL[i] ~= sR[i] then return i end
    i = i + 1
  end
  if #sL < #sR then return #sL + 1 end
  if #sR < #sL then return #sR + 1 end
  return nil
end

local function diffLineCol(linesL, linesR)
  local i = 1
  while i <= #linesL and i <= #linesR do
    local lL, lR = linesL[i], linesR[i]
    if lL ~= lR then
      return i, assert(diffCol(lL, lR))
    end
    i = i + 1
  end
  if #linesL < #linesR then return #linesL + 1, 1 end
  if #linesR < #linesL then return #linesR + 1, 1 end
  return nil
end

M.diffFmt = function(f, sE, sR)
  local linesE = lines(sE)
  local linesR = lines(sR)
  local l, c = diffLineCol(linesE, linesR)
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
