local G = G or _G

--- format module: format any type into a readable string
local M = G.mod and G.mod'fmt' or setmetatable({}, {})

local mty = require'metaty'

local sfmt, srep = string.format, string.rep
local add, concat = table.insert, table.concat
local sort = table.sort
local mathtype = math.type
local sconcat = string.concat -- note: from metaty

local DEPTH_ERROR = '{!max depth reached!}'

--- for comparing two (possibly) different types
--- [$nil < bool < number < string < table]
M.cmpDuck = function(a, b)
  local aTy, bTy = type(a), type(b)
  if aTy ~= bTy then return aTy < bTy end
  return a < b
end
local cmpDuck = M.cmpDuck

--- keywords https://www.lua.org/manual/5.4/manual.html
M.KEYWORD = {}; for kw in string.gmatch([[
and       break     do        else      elseif    end
false     for       function  goto      if        in
local     nil       not       or        repeat    return
then      true      until     while
]], '%w+') do M.KEYWORD[kw] = true end
local KEYWORD = M.KEYWORD


-- TODO: move this over here
local split = mty.split

M.sortKeys = function(t)
  local len, keys = #t, {}
  for k, v in pairs(t) do
    if not (mathtype(k) == 'integer' and (1 <= k) and (k <= len)) then
      add(keys, k)
    end
  end; sort(keys, cmpDuck)
  return keys
end

M.Fmt = mty'Fmt' {
  'style     [bool]: enable styling. If true, set [$to=Styler]',
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
  "_level    [int]",     _level     = 0,
 [[_nl [string] (default='\n') newline, indent is added/removed]],
   _nl = '\n',

  -- overrideable methods
  'table [function]', 'string [function]',
}
local Fmt = M.Fmt

Fmt.pretty = function(F, t)
  t.tableStart = t.tableStart or '{\n'
  t.tableEnd   = t.tableEnd   or '\n}'
  t.listEnd    = t.listEnd    or '\n'
  t.keyEnd     = t.keyEnd     or ',\n'
  t.indent     = t.indent     or '  '
  return F(t)
end

--- add to the indent level and get the new value
--- call with [$add=nil] to just get the current level
Fmt.level = function(f, add) --> int: current level
  local l = f._level
  if add then
    l = l + add; assert(l >= 0, 'fmt._level cannot be negative')
    f._level, f._nl = l, '\n'..srep(f.indent, l)
  end
  return l
end

Fmt.flush = function(f) if f.to then f.to:flush() end end
Fmt._write = function(f, str)
  if f.to then f.to:write(str) else rawset(f, #f + 1, str) end
end
Fmt.write = function(f, ...)
  local str = sconcat('', ...)
  local doIndent = false
  for _, line in split(str, '\n') do
    if doIndent then f:_write(f._nl) end
    f:_write(line); doIndent = true
  end
end
Fmt.styled = function(f, style, text, ...)
  if not f.style then f:write(text, ...); return end
  local to, doIndent = f.to, false
  for _, line in split(text, '\n') do
    if doIndent then f:_write(f._nl) end
    to:styled(style, line); doIndent = true
  end
  doIndent = false
  for _, line in split(sconcat('', ...), '\n') do
    if doIndent then f:_write(f._nl) end
    to:write(line); doIndent = true
  end
end
Fmt.__newindex = function(f, i, v)
  if type(i) ~= 'number' then; assert(f.__fields[i], i)
    return rawset(f, i, v)
  end
  assert(i == #f + 1, 'can only append to Fmt')
  f:write(v)
end

Fmt.tableKey = function(f, k)
  if type(k) ~= 'string' or KEYWORD[k]
     or tonumber(k) or k:find'[^_%w]' then
    add(f, '[');
    if type(k) == 'string' then add(f, sfmt('%q', k)) else f(k) end
    add(f, ']')
  else add(f, k) end
end

Fmt['nil']      = function(f)     add(f, 'nil')             end
Fmt.boolean     = function(f, b)  add(f, tostring(b))       end
Fmt.number      = function(f, n)  add(f, sfmt(f.numfmt, n)) end
Fmt.string      = function(f, s)  add(f, sfmt(f.strfmt, s)) end
Fmt.thread      = function(f, th) add(f, tostring(th))      end
Fmt.userdata    = function(f, ud) add(f, tostring(ud))      end
Fmt['function'] = function(f, fn) add(f, sfmt('fn%q[%s]', mty.fninfo(fn))) end

--- format items in table "list"
Fmt.items = function(f, t, hasKeys, listEnd)
  local len = #t; for i=1,len do
    f(t[i])
    if (i < len) or hasKeys then add(f, f.indexEnd) end
  end
  if listEnd then add(f, listEnd) end
end

--- format key/vals in table "map"
Fmt.keyvals = function(f, t, keys)
  local klen, kset, kend = #keys, f.keySet, f.keyEnd
  for i, k in ipairs(keys) do
    f:tableKey(k); add(f, kset);
    local v = t[k]
    if rawequal(t, v) then add(f, 'self')
    else                   f(v) end
    if i < klen then add(f, kend) end
  end
end

--- Recursively format a table.
--- Yes this is complicated. No, there is no way to really improve
--- this while preserving the features.
Fmt.table = function(f, t)
  if f._level >= f.maxIndent then return add(f, DEPTH_ERROR) end
  local mt, keys = getmetatable(t), nil
  if (mt ~= 'table') and (type(mt) == 'string') then
    return add(f, tostring(t))
  end
  if type(mt) == 'table' then
    local fn = rawget(mt, '__fmt'); if fn then return fn(t, f) end
    fn = rawget(mt, '__tostring');  if fn then return add(f, fn(t)) end
    local n = rawget(mt, '__name'); if n  then add(f, n)       end
    keys = rawget(mt, '__fields')
  end
  keys = keys or M.sortKeys(t)
  local multi = #t + #keys > 1 -- use multiple lines
  f:level(1)
  if multi then add(f, f.tableStart) else add(f, '{') end
  f:items(t, next(keys), multi and (#t>0) and (#keys>0) and f.listEnd)
  f:keyvals(t, keys)
  f:level(-1)
  if multi then add(f, f.tableEnd) else add(f, '}') end
end
Fmt.__call = function(f, v) f[type(v)](f, v); return f end

--- like string.format but use [$Fmt] for [$%q].
--- Doesn't return the string, instead writes to [$Fmt]
Fmt.format = function(f, fmt, ...) --> varargsUsed
  local i, lasti, args = 0, 1, {...}
  fmt:gsub('()(%%.)', function(si, m)
    f:write(fmt:sub(lasti, si-1)); lasti = si + #m
    if m == '%%' then f:write'%'
    else
      i = i + 1;
      if m == '%q' then f(args[i]) else f:write(sfmt(m, args[i])) end
    end
  end)
  f:write(fmt:sub(lasti))
  return i
end

--- fmt ... separated by sep
Fmt.concat = function(f, sep, ...) --> f
  f(select(1, ...))
  for i=2,select('#', ...) do
    add(f, sep); f(select(i, ...))
  end
  return f
end
--- fmt ... separated by tabs
Fmt.tabulated = function(f, ...) return f:concat('\t', ...) end

--- fmt ... separated by newlines
Fmt.lined = function(f, ...) return f:concat('\n', ...) end

Fmt.__tostring = function(f)
  assert(not f.to, 'tostring called while storing to object')
  return concat(f)
end
Fmt.tostring = Fmt.__tostring


M.tostring = function(v, fmt)
  fmt = fmt or Fmt{}; assert(#fmt == 0, 'non-empty Fmt')
  return concat(fmt(v))
end

M.format = function(fmt, ...)
  local f = Fmt{}
  assert(f:format(fmt, ...) == select('#', ...),
         'invalid number of %args')
  return concat(f)
end
local format = M.format

M.errorf  = function(...)    error(format(...), 2)             end
M.assertf = function(a, ...) return a or error(format(...), 2) end

io.fmt = io.fmt or Fmt{to=io.stderr}

M.fprint = function(f, ...)
  local len = select('#', ...)
  for i=1,len do
    local v = select(i, ...)
    if type(v) == 'string' then f:write(v) else f(v) end
    if i < len then f:write'\t' end
  end; f:write'\n'
end
local fprint = M.fprint

--- [$print(...)] but using [$io.fmt]
M.print  = function(...) return fprint(io.fmt, ...) end

--- pretty format the value
M.pretty = function(v) return concat(Fmt:pretty{}(v)) end --> string

--- directly call fmt for better [$tostring]
getmetatable(M).__call = function(_, v) return concat(Fmt{}(v)) end
return M
