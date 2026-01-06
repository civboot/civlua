local G = G or _G

--- format module: format any type into a readable string
local M = G.mod and G.mod'fmt' or setmetatable({}, {})

local mty = require'metaty'

local getmt = getmetatable
local sfmt, srep = string.format, string.rep
local push, concat = table.insert, table.concat
local sort = table.sort
local mathtype = math.type
local split = mty.split

local DEPTH_ERROR = '{!max depth reached!}'

--- valid TTYs. These are used by other libraries
--- to determine if the output can handle color.
M.TTY = {
  [rawget(io, '_stdout') or io.stdout] = 1,
  [rawget(io, '_stderr') or io.stderr] = 2,
}

--- Compares two values of any type.
---
--- Note: [$nil < bool < number < string < table]
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

--- Return a list of the table's keys sorted using [$cmpDuck]
M.sortKeys = function(t) --> list
  local len, keys = #t, {}
  for k, v in pairs(t) do
    if not (mathtype(k) == 'integer' and (1 <= k) and (k <= len)) then
      push(keys, k)
    end
  end; sort(keys, cmpDuck)
  return keys
end

--- The Fmt formatter object.
---
--- This is the main API of this module. It enables formatting any
--- type by simply calling it's instance, appending the result to [$f] (i.e.
--- self) or (if present) writing the result to [$f.to].
---
--- If [$f.to] is not provided, you can get the resulting string by calling
--- [$tostring(f)]
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

Fmt.toPretty = function(f)
  f.tableStart = rawget(f, 'tableStart') or '{\n'
  f.tableEnd   = rawget(f, 'tableEnd')   or '\n}'
  f.listEnd    = rawget(f, 'listEnd')    or '\n'
  f.keyEnd     = rawget(f, 'keyEnd')     or ',\n'
  f.indent     = rawget(f, 'indent')     or '  '
  return f
end

--- Create a new Formatter object with default "pretty" settings.
--- Generally, this means line-separated and indented tables.
Fmt.pretty = function(F, t) return F(t):toPretty() end

--- Add to the indent level and get the new value
--- call with [$add=nil] to just get the current level
Fmt.level = function(f, add) --> int: current level
  local l = f._level
  if add then
    l = l + add; assert(l >= 0, 'fmt._level cannot be negative')
    f._level, f._nl = l, '\n'..srep(f.indent, l)
  end
  return l
end

Fmt._write = function(f, str)
  if f.to then f.to:write(str) else rawset(f, #f + 1, str) end
end
--- Same as [$file:write].
function Fmt:write(...)
  local str = concat{...}
  local doIndent = false
  for _, line in split(str, '\n') do
    if doIndent then self:_write(self._nl) end
    self:_write(line); doIndent = true
  end
  return self
end
function Fmt:flush() if self.to then self.to:flush() end; return true end
function Fmt:close() if self.to then self.to:close() end; return true end

--- Call [$to:styled(...)] if it is enabled, else simply [$f:write(text, ...)].
--- This allows for configurable styling of output, both for objects as well
--- as command-line utilities/etc.
Fmt.styled = function(f, style, text, ...)
  if not f.style then f:write(text, ...); return end
  local to, doIndent = f.to, false
  for _, line in split(text, '\n') do
    if doIndent then f:_write(f._nl) end
    to:styled(style, line); doIndent = true
  end
  doIndent = false
  for _, line in split(concat{...}, '\n') do
    if doIndent then f:_write(f._nl) end
    to:write(line); doIndent = true
  end
end

Fmt.__newindex = function(f, k, v)
  assert(type(k) == 'string', 'cannot set Fmt index')
  return rawset(f, k, v)
end

--- Format like a table key. This can be overriden by type extensions to
--- provide other behavior.
Fmt.tableKey = function(f, k)
  if type(k) ~= 'string' or KEYWORD[k]
     or tonumber(k) or k:find'[^_%w]' then
    f:styled('meta', '[')
    if type(k) == 'string' then f:styled('string', sfmt('%q', k))
    else                        f(k) end
    f:styled('meta', ']', '')
  else f:styled('key', k, '') end
end

--- format a nil value.
Fmt['nil']      = function(f)
  f:styled('literal', 'nil', '')
end
--- format a boolean value.
Fmt.boolean     = function(f, b)
  f:styled('literal', tostring(b), '')
end
--- format a number value.
Fmt.number      = function(f, n)
  f:styled('num', sfmt(f.numfmt, n), '')
end
--- format a string value.
Fmt.string      = function(f, s)
  f:styled('string', sfmt(f.strfmt, s), '')
end
--- format a thread value.
Fmt.thread      = function(f, th)
  f:styled('literal', tostring(th), '')
end
--- format a userdata value.
Fmt.userdata    = function(f, ud)
  f:styled('literal', tostring(ud), '')
end
--- format a function value.
Fmt['function'] = function(f, fn)
  f:styled('path', sfmt('fn%q[%s]', mty.fninfo(fn)), '')
end

--- format items in table "list"
Fmt.items = function(f, t, hasKeys, listEnd)
  local len = #t; for i=1,len do
    f(t[i])
    if (i < len) or hasKeys then f:styled('meta', f.indexEnd, '') end
  end
  if listEnd then f:styled('meta', listEnd, '') end
end

--- format key/vals in table "map"
Fmt.keyvals = function(f, t, keys)
  local klen, kset, kend = #keys, f.keySet, f.keyEnd
  for i, k in ipairs(keys) do
    f:tableKey(k); f:write(kset)
    local v = t[k]
    if rawequal(t, v) then f:styled('keyword', 'self', '')
    else                   f(v) end
    if i < klen then f:styled('meta', kend, '') end
  end
end

--- Format only the list-elements of a table.
Fmt.list = function(f, t)
  local multi = #t > 1
  f:level(1)
  f:styled('symbol', multi and f.tableStart or '{', '')
  f:items(t, false,  nil)
  f:level(-1)
  f:styled('symbol', multi and f.tableEnd or '}', '')
end

Fmt.rawtable = function(f, t)
  local keys = M.sortKeys(t)
  local multi = #t + #keys > 1 -- use multiple lines
  f:level(1)
  f:styled('symbol', multi and f.tableStart or '{', '')
  f:items(t, next(keys), multi and (#t>0) and (#keys>0) and f.listEnd)
  f:keyvals(t, keys)
  f:level(-1)
  f:styled('symbol', multi and f.tableEnd or '}', '')
end

--- Recursively format a table.
--- Yes this is complicated. No, there is no way to really improve
--- this while preserving the features.
Fmt.table = function(f, t)
  if f._level >= f.maxIndent then return f:write(DEPTH_ERROR) end
  local mt = getmt(t)
  if (mt ~= 'table') and (type(mt) == 'string') then
    return f:write(tostring(t))
  end
  if type(mt) == 'table' then
    local fn = rawget(mt, '__fmt'); if fn then return fn(t, f) end
    fn = rawget(mt, '__tostring');  if fn then return f:write(fn(t)) end
    local name = rawget(mt, '__name'); if name then f:write(name) end
  end
  return f:rawtable(t)
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
    f:write(sep); f(select(i, ...))
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

M.fprint = function(f, ...)
  assert(f, 'must set f')
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

--- pretty print
M.pprint = function(...)
  local f; if io.fmt then
    f = {}
    for k,v in pairs(io.fmt) do f[k] = v end
    setmetatable(f, getmetatable(io.fmt))
    f:toPretty()
  end
  return M.fprint(f, ...)
end

--- pretty format the value
M.pretty = function(v) return concat(Fmt:pretty{}(v)) end --> string

--- Set to __fmt to format a type like a table.
M.table = function(tbl, f) return f:rawtable(tbl) end

--- directly call fmt for better [$tostring]
getmt(M).__call = function(_, v) return concat(Fmt{}(v)) end
return M
