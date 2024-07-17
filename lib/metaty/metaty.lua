-- metaty: simple but effective Lua type system using metatable
--
-- See README.md for documentation.
local M = (mod and mod'metaty' or {})
setmetatable(M, getmetatable(M) or {})

local function copy(t)
  local o = {}; for k, v in pairs(t) do o[k] = v end; return o
end

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
  return _G[var]
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
  return type(o) == 'function' and M.fninfo(o)
      or type(t) == 'table'    and M.tyName(M.ty(o))
      or type(t) == 'userdata' and M.tyName(getmetatable(o), 'userdata')
      or nil
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
  end
  return fields
end


M.namedRecord = function(name, R, loc)
  rawset(R, '__name', name)
  R.__fields = M.extendFields({}, R)
  R.__index  = rawget(R, '__index') or R
  local mt = {
    __name='Ty<'..R.__name..'>',
    __newindex=mod and mod.__newindex,
  }
  local R = setmetatable(R, mt)
  if METATY_CHECK then
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

------------------
-- Fmt
M.sortKeys = function(t)
  local len, keys = #t, {}
  for k, v in pairs(t) do
    if not (math.type(k) == 'integer' and (1 <= k) and (k <= len)) then
      add(keys, k)
    end
  end; table.sort(keys)
  return keys
end

M.Fmt = M.record'Fmt' {
  "to        [file?]: if set calls write",
  "keyEnd    [string]",  keyEnd     = ', ',
  "keySet    [string]",  keySet     = '=',
  "indexEnd  [string]",  indexEnd   = ', ',
  "tableStart[string]",  tableStart = '{',
  "tableEnd  [string]",  tableEnd   = '}',
  "listEnd   [string] separator between list/map", listEnd    = '',
  "indent    [string]",  indent     = '  ',
  "maxIndent [int]",     maxIndent  = 20,
  "numfmt    [string]",  numfmt     = '%q',
  "strfmt    [string]",  strfmt     = '%q',
  "_depth    [int]",     _depth     = 0,
 [[_nl [string] (default='\n') newline, indent is added/removed]],
   _nl = '\n',

  -- overrideable methods
  'table [function]', 'string [function]',
}

M.Fmt.pretty = function(F, t)
  t.tableStart = t.tableStart or '{\n'
  t.tableEnd   = t.tableEnd   or '\n}'
  t.listEnd    = t.listEnd    or '\n'
  t.keyEnd     = t.keyEnd     or ',\n'
  t.indent     = t.indent     or '  '
  return F(t)
end

M.Fmt.incIndent = function(f)
  f._depth = f._depth + 1
  if f.indent then f._nl = f._nl..f.indent end
end
M.Fmt.decIndent = function(f)
  if f._depth <= 0 then error'unballanced indent' end
  f._depth = f._depth - 1
  local ind = f.indent; if not ind then return end
  f._nl = f._nl:sub(1, -1 - #ind); assert(f._nl:sub(1,1) == '\n')
end
M.Fmt.write = function(f, ...)
  if f.to then f.to:write(...); return end
  local s = (select('#', ...) == 1) and (...) or table.concat{...}
  rawset(f, #f + 1, s)
end
M.Fmt.__newindex = function(f, i, v)
  if type(i) ~= 'number' then; assert(f.__fields[i], i)
    return rawset(f, i, v)
  end
  assert(i == #f + 1, 'can only append to Fmt')
  local doIndent = false
  for _, line in M.split(v, '\n') do
    if doIndent then f:write(f._nl) end
    f:write(line); doIndent = true
  end
end
M.Fmt.tableKey = function(f, k)
  if type(k) ~= 'string' or M.KEYWORD[k]
     or tonumber(k) or k:find'[^_%w]' then
    add(f, '[');
    if type(k) == 'string' then add(f, sfmt('%q', k)) else f(k) end
    add(f, ']')
  else add(f, k) end
end
M.Fmt['nil']      = function(f)     add(f, 'nil')             end
M.Fmt.boolean     = function(f, b)  add(f, tostring(b))       end
M.Fmt.number      = function(f, n)  add(f, sfmt(f.numfmt, n)) end
M.Fmt.string      = function(f, s)  add(f, sfmt(f.strfmt, s)) end
M.Fmt.thread      = function(f, th) add(f, tostring(th))      end
M.Fmt.userdata    = function(f, ud) add(f, tostring(ud))      end
M.Fmt['function'] = function(f, fn) add(f, sfmt('fn%q[%s]', M.fninfo(fn))) end

-- format items in table "list"
M.Fmt.items = function(f, t, hasKeys, listEnd)
  local len = #t; for i=1,len do
    f(t[i])
    if (i < len) or hasKeys then add(f, f.indexEnd) end
  end
  if listEnd then add(f, listEnd) end
end

-- format key/vals in table "map"
M.Fmt.keyvals = function(f, t, keys)
  local klen, kset, kend = #keys, f.keySet, f.keyEnd
  for i, k in ipairs(keys) do
    f:tableKey(k); add(f, kset);
    local v = t[k]
    if rawequal(t, v) then add(f, 'self')
    else                   f(v) end
    if i < klen then add(f, kend) end
  end
end

-- Recursively format a table.
-- Yes this is complicated. No, there is no way to really improve
-- this while preserving the features.
M.Fmt.table = function(f, t)
  if f._depth >= f.maxIndent then return add(f, M.DEPTH_ERROR) end
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
  keys = keys or M.sortKeys(t)
  local multi = #t + #keys > 1 -- use multiple lines
  f:incIndent()
  if multi then add(f, f.tableStart) else add(f, '{') end
  f:items(t, next(keys), multi and (#t>0) and (#keys>0) and f.listEnd)
  f:keyvals(t, keys)
  f:decIndent()
  if multi then add(f, f.tableEnd) else add(f, '}') end
end
M.Fmt.__call = function(f, v) f[type(v)](f, v); return f end

M.tostring = function(v, fmt)
  fmt = fmt or M.Fmt{}; assert(#fmt == 0, 'non-empty Fmt')
  return table.concat(fmt(v))
end

M.format = function(fmt, ...)
  local i, args, tc = 0, {...}, table.concat
  local out = fmt:gsub('%%.', function(m)
    if m == '%%' then return '%' end
    i = i + 1
    return m ~= '%q' and sfmt(m, args[i])
      or tc(M.Fmt{}(args[i]))
  end)
  assert(i == #args, 'invalid #args')
  return out
end

M.fprint = function(f, ...)
  local len = select('#', ...)
  for i=1,len do
    local v = select(i, ...)
    if type(v) == 'string' then f:write(v) else f(v) end
    if i < len then f:write'\t' end
  end; f:write'\n'
end


-- print(...) but with Fmt
M.print  = function(...) return M.fprint(M.Fmt{to=io.stdout}, ...) end
-- pretty print(...) with Fmt:pretty
M.pprint = function(...) return M.fprint(M.Fmt:pretty{to=io.stdout}, ...) end
M.eprint = function(...) return M.fprint(M.Fmt{to=io.stderr}, ...) end

M.errorf  = function(...)    error(M.format(...), 2)             end
M.assertf = function(a, ...) return a or error(M.format(...), 2) end

return M
