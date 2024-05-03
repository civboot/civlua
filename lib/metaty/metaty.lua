-- metaty: simple but effective Lua type system using metatable
--
-- See README.md for documentation.
local M = (mod and mod'metaty' or {})

---------------
-- Pre module: environment variables
local IS_ENV = { ['true']=true,   ['1']=true,
                 ['false']=false, ['0']=false, ['']=false }

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

---------------
-- general functions and constants
FIELD_DOC = FIELD_DOC or {}
M.DEPTH_ERROR = '{!max depth reached!}'
local add, sfmt = table.insert, string.format

M.ty = function(o) --> Type: string or metatable
  local t = type(o)
  return t == 'table' and getmetatable(o) or t
end

-- Given a type return it's name
M.tyName = function(T) --> name
  local Tty = type(T)
  return Tty == 'string' and T
    or ((Tty == 'table') and rawget(T, '__name'))
    or Tty
end

M.callable = function(obj) --> bool: return if obj is callable
  if type(obj) == 'function' then return true end
  local m = getmetatable(obj); return m and rawget(m, '__call')
end
M.metaget = function(t, k)   return rawget(getmetatable(t), k) end
M.errorf  = function(...)    error(string.format(...), 2)      end
M.assertf = function(a, ...) return a or error(sfmt(...), 2)   end

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
  local loc = PKG_LOCSS[fn]; if not loc then
    info = info or debug.getinfo(fn)
    loc = string.format('%s:%s', info.short_src, info.linedefined)
  end
  return name, loc
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

M.namedRecord = function(name, R, loc)
  rawset(R, '__name', name)
  local fields = {}; for i=1,#R do
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
  R.__fields = fields
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

M.record2 = function(name)
  assert(type(name) == 'string' and #name > 0,
         'must set __name=string')
  return function(R) return M.namedRecord(name, R) end
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
  "keyEnd    [string]",  keyEnd=', ',
  "indexEnd  [string]",  indexEnd = ', ',
  "tableStart[string]",  tableStart = '{',
  "tableEnd  [string]",  tableEnd = '}',
  "listEnd   [string] separator between list/map", listEnd    = '',
  "indent    [string]",  indent = '  ',
  "maxIndent [int]",     maxIndent = 20,
  "numfmt    [string]",  numfmt = '%q',
  "strfmt    [string]",  strfmt = '%q',
  "_depth    [int]",     _depth = 0,
 [[_nl [string] (default='\n') newline, indent is added/removed]],
   _nl = '\n',
}

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
M.Fmt2.thread      = function(f, th) add(f, tostring(th))      end
M.Fmt2.userdata    = function(f, ud) add(f, tostring(ud))      end
M.Fmt2['function'] = function(f, fn) add(f, sfmt('fn%q[%s]', M.fninfo(fn))) end

-- Recursively format a table.
-- Yes this is complicated. No, there is no way to really improve
-- this while preserving the features.
M.Fmt2.table = function(f, t)
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
  print(table.concat(f))
end

return M
