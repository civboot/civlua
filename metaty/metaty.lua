-- metaty: simple but effective Lua type system using metatable
--
-- See README.md for documentation.

-- Utilities / aliases
local add, sfmt = table.insert, string.format
local function identity(v) return v end
local function nativeEq(a, b) return a == b end
local function copy(t) -- shallow copy
  if type(t) ~= 'table' then return t end
  local x = {}; for k, v in pairs(t) do x[k] = v end
  return x
end
local function lines(text)
  local out = {}; for _, l in text:gmatch'[^\n]*' do add(out, l) end
  return out
end

local M = {}
M.CHECK = _G['METATY_CHECK'] or false
M.KEYS_MAX = 64
M.FMT_SAFE = false

M.errorf  = function(...) error(string.format(...)) end
M.assertf = function(a, ...) if not a then assert(a, sfmt(...)) end end

-- Lookup tables for ty / tyName
M.Any = setmetatable({__name='Any'}, {
  __name='AnyTy', __tostring=function() return 'Any' end
})
M.Unset = setmetatable({__name='Unset'}, {
  __name='UnsetTy', __tostring=function() return 'Unset' end
})
M.ANY = { [M.Any] = true }
local TY_MAP = {
  ['function'] = function()  return 'function' end,
  ['nil']      = function()  return 'nil' end,
  boolean      = function()  return 'boolean' end,
  number       = function()  return 'number' end,
  string       = function()  return 'string' end,
  table        = function(t) return getmetatable(t) or 'table' end,
}
local TY_NAME = {}; for k in pairs(TY_MAP) do TY_NAME[k] = k end
local TY_CHECK = {
  ['nil'] = nativeEq, ['function'] = nativeEq,
  boolean = nativeEq, number = nativeEq, string = nativeEq,
}

-- Return type which is the metatable (if it exists) or raw type() string.
M.ty = function(obj) return TY_MAP[type(obj)](obj) end

-- Safely get the name of type
M.tyName = function(ty_) --> string
  return TY_NAME[ty_] or rawget(ty_, '__name') or 'table'
end

M.tyCheck = function(aTy, bTy) --> bool
  local x = TY_CHECK[aTy]; if x then return x(aTy, bTy) end
  return M.ANY[aTy] or M.ANY[bTy] or (aTy == bTy)
end

M.tyError = function(expectTy, resultTy) --> !error
  M.errorf("Types do not match: %s :: %s",
         M.tyName(expectTy), M.tyName(resultTy))
end

----------------------------------------------
-- rawTy: create new types

-- Ultra-simple index function
M.metaindex = function(self, k) return getmetatable(self)[k] end

-- __index function for most types
-- Set metatable.__missing to type check on missing keys.
M.index = function(self, k) --> any
  local mt = getmetatable(self)
  local x = rawget(mt, k); if x then return x end
  x = rawget(mt, '__missing')
  return x and x(self, k) or nil
end


M.fieldMissing = function(self, k)
  M.errorf('Invalid field on %s: %s', M.tyName(M.ty(self)), k)
end

-- These are the default constructor functions
M.newUnchecked = function(ty_, t) return setmetatable(t, ty_) end
M.newChecked   = function(ty_, t)
  local tys = ty_.__tys
  for field, v in pairs(t) do
    if not M.tyCheck(tys[field], M.ty(v)) then
      M.tyError(M.ty(v), tys[field] or '<field not specified>')
    end
  end
  return setmetatable(t, ty_)
end
M.selectNew = function() return M.CHECK and M.newChecked or M.newUnchecked end

-- MyType = rawTy('MyType', {new=function(ty_, t) ... end})
M.rawTy = function(name, mt)
  mt = mt or {}
  mt.__name = mt.__name or sfmt("Ty<%s>", name)
  mt.__call = mt.__call or M.selectNew()
  local ty_ = {
    __name=name,
    __index=M.index,
    __fmt=M.tblFmt,
    __tys={}, -- field types
  }
  return setmetatable(ty_, mt)
end

----------------------------------------------
-- record: create record types

M.recordField = function(r, name, ty_, default)
  assert(name, "must provide field name")
  M.assertf(not r.__tys[name], 'Attempted override of field: %s', name)
  M.assertf(not r.name, 'Attempted override of method with field: %s', name)
  ty_ = ty_ or M.Any

  r.__tys[name] = ty_ -- track the type name
  if nil ~= default then
    M.tyCheck(ty_, M.ty(default))
    r[name] = default
  end
  add(r.__fields, name) -- for in-order formatting
  return r
end

M.record = function(name, mt)
  local r = M.rawTy(name, mt)
  -- for k, v in pairs(prototype or {}) do r[k] = copy(v) end
  r.__fields = r.__fields or {}

  local mt = getmetatable(r)
  mt.field = M.recordField
  mt.__index = M.metaindex
  return r
end

----------------------------------------------
-- Equality

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

-- modified from: https://www.lua.org/manual/5.1/manual.html
M.geteventhandler = function(a, b, event)
  return (getmetatable(a) or {})[event] or (getmetatable(b) or {})[event]
end

local EQ_TY = {
  number = nativeEq, boolean = nativeEq, string = nativeEq,
  ['nil'] = nativeEq, ['function'] = nativeEq,
  ['table'] = function(a, b)
    if M.geteventhandler(a, b, '__eq') then return a == b end
    if a == b                          then return true   end
    return M.eqDeep(a, b)
  end,
}
M.eq = function(a, b) return EQ_TY[type(a)](a, b) end

----------------------------------------------
-- Formatting

-----------
-- Fmt Object itself
M.FMT_NEW = M.selectNew()

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
  end
})
  :field('done', 'table')
  :field('level', 'number', 0)
  :field('set', M.FmtSet, M.DEFAULT_FMT_SET)
M.Fmt.__fmt = nil

M.Fmt.__missing = function(self, k)
  if type(k) == 'number' then return nil end
  return M.fieldMissing(self, k)
end

-----------
-- Fmt Utilities

M.fnToStr = function(fn)
  local s = debug.getinfo(fn, 'nS')
  local n = ''; if s.name then n = sfmt('%q', s.name) end
  return sfmt('Fn%s@%s:%s', n, s.short_src, s.linedefined)
end

local function orderedKeys(t, max) --> table (ordered list of keys)
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
  return tostring(t):gsub('table: ', '')
end

M.metaName = function(mt)
  if not mt then return '' end
  return mt.__name or '?'
end

M.tblToStrSafe = function(t)
  local mt = getmetatable(t);
  if not mt then return sfmt('Tbl@%s', M.tblIdUnsafe(t)) end
  if mt.__tostring then return sfmt('%s{...}', M.metaName(mt)) end
  return sfmt('%s@%s', M.metaName(mt), M.tblIdUnsafe(t))
end

M.SAFE_TOSTRING = {
  ['nil']=function(n) return 'nil' end,
  ['function']=M.fnToStr,
  boolean=function(v, set) return tostring(v) end,
  number=function(n, set)
    local f = '%i'
    if set then f = set.num or '%i' end
    return sfmt(f, n)
  end,
  string=function(s)
    if M.strIsAmbiguous(s) then return sfmt('%q', s) end
    return s
  end,
  table=M.tblToStrSafe,
}

M.safeToStr = function(v, set) --> string
  return M.SAFE_TOSTRING[type(v)](v, set)
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

  local keys = orderedKeys(t, f.set.keysMax)
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
M.FmtSet.__fmt = M.tblFmt -- note: normal default but was nil

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
    add(f, M.SAFE_TOSTRING[tystr](v, f.set))
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

M.diffLineCol = function(linesL, linesR)
  local i = 1
  while i <= #linesL and i <= #linesR do
    local lL, lR = linesL[i], linesR[i]
    if lL ~= lR then
      return i, assert(strDiffPlace(lL, lR))
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
  local l, c = M.diffLineCol(linesE, linesR)
  assert(l); assert(c)
  add(f, sfmt("! Difference line=%q (", l))
  add(f, sfmt('lines[%q|%q]', #linesE, #linesR))
  add(f, sfmt(' strlen[%q|%q])\n', #sE, #sR))
  add(f, '! EXPECT: '); add(f, linesE[l]); add(f, '\n')
  add(f, '! RESULT: '); add(f, linesR[l]); add(f, '\n')
  add(f, string.rep(' ', c - 1 + 7))
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

return M
