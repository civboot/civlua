-- metaty: simple but effective Lua type system using metatable
--
-- See README.md for documentation.

DOC       = DOC       or {}
FIELD_DOC = FIELD_DOC or {}
local add, sfmt = table.insert, string.format

local M = {}
M.DEPTH_ERROR = '{!max depth reached!}'

M.ty = function(o)
  local t = type(o)
  return t == 'table' and getmetatable(o) or t
end
M.tyName = function(T)
  local Tty = type(T)
  return Tty == 'string' and T
    or ((Tty == 'table') and rawget(T, '__name'))
    or Tty
end

M.callable = function(obj)
  if type(obj) == 'function' then return true end
  local m = getmetatable(obj); return m and rawget(m, '__call')
end
M.metaget = function(t, k) return rawget(getmetatable(t), k) end
M.errorf = function(...) error(string.format(...), 2) end
M.assertf = function(a, ...)
  if not a then error('assertf: '..string.format(...), 2) end
  return a
end

-- keywords https://www.lua.org/manual/5.4/manual.html
M.KEYWORD = {}; for kw in string.gmatch([[
and       break     do        else      elseif    end
false     for       function  goto      if        in
local     nil       not       or        repeat    return
then      true      until     while
]], '%w+') do M.KEYWORD[kw] = true end

M.validKey = function(s) --> boolean
  return type(s) == 'string' and
    not (M.KEYWORD[s] or tonumber(s)
         or s:find'[^_%w]')
end

M.fnString = function(fn)
  local t = {'Fn'}
  local dbg = debug.getinfo(fn, 'nS')
  if dbg.name then add(t, sfmt('%q', dbg.name)) end
  add(t, '@'); add(t, dbg.short_src);
  add(t, ':'); add(t, tostring(dbg.linedefined));
  return table.concat(t)
end

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

local CHECK  = M.isEnvG'METATY_CHECK' or false -- private
local _doc   = M.isEnvG'METATY_DOC'   or false -- private
M.getCheck = function() return CHECK end
M.getDoc   = function() return _doc  end

----------------------
-- Documentation
M.CONCRETE_TYPE = {['nil']=true, bool=true, number=true, string=true}
function M.identity(v) return v end
function M.trim(subj, pat, index)
  pat = pat and ('^'..pat..'*(.-)'..pat..'*$') or '^%s*(.-)%s*$'
  return subj:match(pat, index)
end

function M.steal(t, k) local v = t[k]; t[k] = nil; return v end
function M.nativeEq(a, b) return a == b end
function M.docTy(T, doc)
  if M.CONCRETE_TYPE[type(T)] then
    error('cannot document '..tostring(T), 2)
  end
  if not _doc then return T end
  DOC[T] = M.trim(doc)
  return T
end
function M.doc(doc)
  return function(T) return M.docTy(T, doc) end
end
M.docTy(M.isEnvG,  'isEnvG"MY_VAR": isEnv but also checks _G')
M.docTy(M.isEnv,  [[isEnv"MY_VAR" -> boolean (environment variable)
  true: 'true' '1'    false: 'false' '0' '']])
M.docTy(M.steal,   'steal(t, key): return t[key] and remove it')
M.docTy(M.trim, [[trim(subj, pat='%s', index=1) -> string
  removes pat from front+back of string]])
M.docTy(M.doc, [==[
Document a type, example:
  M.myFn = doc[[myFn is awesome!
  It does ... stuff with a and b.
  ]](function(a, b)
    ...
  end)
]==])
M.docTy(M.docTy, [==[
docTy(ty_, doc): Document a type, prefer `doc` instead.
Example: docTy(myTy, [[my doc string]])
]==])

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
]](function(subj, pat, index)
  return rawsplit, subj, {pat or '%s+', index or 1}
end)


-----------------------------
-- Equality

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

-----------------------
-- record2
M.index = function(R, k) -- Note: R is record's metatable
  if type(k) == 'string' and not rawget(R, '__fields')[k] then
    error(R.__name..' does not have field '..k, 2)
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
    local name, tyname, fdoc =
      spec:match'^([%w_]+)%s*(%b[])%s*:?%s*(.*)$'
    if not name then
      name, fdoc = spec:match'^([%w_]+)%s*:?%s*(.*)$'
    end
    assert(name,      'invalid spec')
    assert(#name > 0, 'empty name')
    add(fields, name); fields[name] = tyname or true
    if #fdoc > 0 then fdocs[name] = fdoc end
  end

  if next(fdocs) then FIELD_DOC[name] = fdocs end
  local mt = { __name='Ty<'..name..'>' }
  local R = setmetatable({
    __name=name, __fields=fields,
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

------------------
-- Fmt
M.tableKey = function(k)
  return M.validKey(k) and k or sfmt('[%q]', k)
end
M.sortKeys = function(t, len)
  len = len or #t; local keys = {}
  for k, v in pairs(t) do
    if not (math.type(k) == 'integer' and k <= len) then
      add(keys, k)
    end
  end; table.sort(keys)
  return keys
end

M.Fmt2 = M.record2'Fmt' {
  "keyEnd    [string] (default=', ')",
  "indexEnd  [string] (default=', ')",
  "tableStart[string] (default='{')",
  "tableEnd  [string] (default='}')",
  "listEnd   [string] (default='') separator between list/map",
  "indent    [string] (default=nil)",
  "maxDepth  [int]    (default=20) maximum depth in tables",
  "numfmt    [string] (default='%q')",
  "strfmt    [string] (default='%q')",
  "_depth    [int]    (default=0)",
 [[_nl [string] (default='\n') newline, indent is added/removed]],
}; for k, v in pairs{
  keyEnd     = ', ',  indexEnd = ', ',
  tableStart = '{',   tableEnd = '}',
  listEnd    = '',
  indent     = '  ',  maxDepth = 20,
  numfmt     = '%q',  strfmt   = '%q',
  _depth     = 0,     _nl = '\n',
} do M.Fmt2[k] = v end
M.Fmt2.pretty = function(F, t)
  t.tableStart = t.tableStart or '{\n'
  t.tableEnd   = t.tableEnd   or '\n}'
  t.listEnd    = t.listEnd    or '\n'
  t.keyEnd     = t.keyEnd     or ',\n'
  t.indent     = t.indent     or '  '
  return F(t)
end

M.Fmt2.incIndent = function(f)
  f._depth = f._depth + 1
  if f.indent then f._nl = f._nl..f.indent end
end
M.Fmt2.decIndent = function(f)
  if f._depth <= 0 then error'unballanced indent' end
  f._depth = f._depth - 1
  local ind = f.indent; if not ind then return end
  f._nl = f._nl:sub(1, -1 - #ind); assert(f._nl:sub(1,1) == '\n')
end
M.Fmt2.write = function(f, ...) add(f, table.concat{...}) end
M.Fmt2.__newindex = function(f, i, v)
  if type(i) ~= 'number' then; assert(f.__fields[i], i)
    return rawset(f, i, v)
  end
  assert(i == #f + 1, 'can only append to Fmt2')
  local doIndent = false
  for _, line in M.split(v, '\n') do
    if doIndent then
      rawset(f, i, f._nl); i = i + 1 end
    rawset(f, i, line); i = i + 1; doIndent = true
  end
end
M.Fmt2.tableKey = function(f, k)
  if type(k) ~= 'string' or M.KEYWORD[k]
     or tonumber(k) or k:find'[^_%w]' then
    add(f, '['); f(k); add(f, ']')
  else add(f, k) end
end
M.Fmt2['nil']      = function(f)     add(f, 'nil')             end
M.Fmt2.boolean     = function(f, b)  add(f, tostring(b))       end
M.Fmt2.number      = function(f, n)  add(f, sfmt(f.numfmt, n)) end
M.Fmt2.string      = function(f, s)  add(f, sfmt(f.strfmt, s)) end
M.Fmt2['function'] = function(f, fn) add(f, M.fnString(fn))    end
M.Fmt2.thread      = function(f, th) add(f, tostring(th))      end
M.Fmt2.userdata    = function(f, ud) add(f, tostring(ud))      end

-- Recursively format a table.
-- Yes this is complicated. No, there is no way to really improve
-- this while preserving the features.
M.Fmt2.table = function(f, t)
  if f._depth >= f.maxDepth then return add(f, M.DEPTH_ERROR) end
  local mt, keys = getmetatable(t), nil
  if (mt ~= 'table') and (type(mt) == 'string') then
    return add(f, tostring(t))
  end
  if type(mt) == 'table' then
    local fn = rawget(mt, '__fmt'); if fn then return fn(t, f) end
     fn = rawget(mt, '__tostring'); if fn then return add(f, fn(t)) end
    local n = rawget(mt, '__name'); if n  then add(f, n)       end
    keys = rawget(mt, '__fields')
  end
  local len = #t; keys = keys or M.sortKeys(t, len)
  f:incIndent()
  if #keys + len > 1 then add(f, f.tableStart) else add(f, '{') end
  for i=1,len do
    f(t[i])
    if (i < len) or next(keys) then add(f, f.indexEnd) end
  end
  if (len > 0) and (#keys + len > 1) then add(f, f.listEnd) end
  for i, k in ipairs(keys) do
    f:tableKey(k); add(f, '=');
    local v = t[k]
    if rawequal(t, v) then add(f, 'self')
    else                   f(v) end
    if i < #keys then add(f, f.keyEnd) end
  end
  f:decIndent()
  if #keys + len > 1 then add(f, f.tableEnd) else add(f, '}') end
end
M.Fmt2.__call = function(f, v) return f[type(v)](f, v) end

M.tostring = function(v, fmt)
  fmt = fmt or M.Fmt2{}; assert(#fmt == 0, 'non-empty Fmt')
  fmt(v)
  return table.concat(fmt)
end

M.format = function(s, ...)
  local i, args = 0, {...}
  return s:gsub('%%.', function(m)
    if m == '%%' then return '%' end
    i = i + 1; if m ~= '%q' then return sfmt(m, args[i]) end
    local f = M.Fmt2{}; f(args[i])
    return table.concat(f)
  end)
end

M.print = function(...)
  local f, len = M.Fmt2{}, select('#', ...)
  for i=1,len do
    f(select(i)); if i < len then add(f, '\t') end
  end
  add(f, '\n')
  io.stdout:write(table.concat(f))
end

--------------------
-- Help

function M.simpleDoc(v, fmt, name)
  if name then fmt:string(name); add(fmt, ': ') end
  fmt:string(type(v))
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
      if fmt.level > 1 and DOC[f] then
        fmt:fmt(string.rep(' ', 36 - #name));
        fmt:fmt'(DOC) '
      else fmt:fmt(string.rep(' ', 42 - #name)) end
      add(fmt, ': ')
    end
    add(fmt, 'function ['); fmt:fmt(f); add(fmt, ']')
    if fmt.level > 1 then return end
    local d = DOC[f]; if d then
      fmt:levelEnter''; fmt:fmt(d); fmt:levelLeave''
    else fmt:sep'\n' end
    return true
  end,
}

M.help2 = M.doc'(v) -> string: Get help'
(function(v)
  local name; if type(v) == 'string' then
    name, v = v, require(v)
  end
  local f = M.Fmt2:pretty()
  if type(v) == 'table' then helpTy(v, f, name)
  else NATIVE_TY_DOC[type(v)](v, f) end
  return M.trim(table.concat(f))
end)

return M
