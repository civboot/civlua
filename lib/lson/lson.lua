
local M = mod and mod'lson' or {}
local mty = require'metaty'
local ds = require'ds'
local empty = ds.empty
local push, sfmt = table.insert, string.format

-- Encoder (via metaty.Fmt)
-- This works identically to metaty.Fmt except it overrides
-- how tables are formatted to use JSON instead.
M.Encoder = mty.extend(mty.Fmt, 'Encoder', {
  'listStart [string]', listStart = '[',
  'listEnd [string]',   listEnd   = ']',
})
M.Encoder.pretty = function(E, t)
  print('!! E.pretty', E, t, getmetatable(E))
  t.listStart = t.listStart or '[\n'
  t.listEnd =   t.listEnd   or '\n]'
  return mty.Fmt.pretty(E, t)
end

local CTRL_SUB = {['\n'] = '\\n', ['\t'] = '\\t'}
M.Encoder.string = function(enc, s)
  push(enc, sfmt('%q', s):gsub('[\n\t]', CTRL_SUB))
end
M.Encoder.table = function(f, t)
  if f._depth >= f.maxIndent then
    error'max depth reached (recursion?)'
  end
  local mt, keys = getmetatable(t)
  if type(mt) == 'table' then
    keys = rawget(mt, '__fields')
  end
  keys = keys or mty.sortKeys(t)
  f:incIndent()
  print('!! Encoder.table', #t, #keys)
  if #keys == 0 then
    if #t > 1 then push(f, f.listStart) else push(f, '[') end
    f:items(t, next(keys)); f:decIndent()
    if #t > 1 then push(f, f.listEnd)   else push(f, ']') end
  else -- has non-list keys
    for i in ipairs(t) do push(keys, i) end
    if #keys > 1 then push(f, f.tableStart) else push(f, '{') end
    f:keyvals(t, keys); f:decIndent()
    if #keys > 1 then push(f, f.tableEnd)   else push(f, '}') end
  end
end
M.Encoder.__call = function(f, v)
  mty.print('!! Encoder call', f.__name, v, type(v), f[type(v)])
  f[type(v)](f, v); return f
end

-------------------------------
-- Decoder
local eval = function(s) return load('return '..s, nil, 't', empty) end

M.pNull  = function(de) de:consume'^null';  return de.null end
M.pTrue  = function(de) de:consume'^true';  return true    end
M.pFalse = function(de) de:consume'^false'; return false   end
M.pNumber = function(de)
  error'not yet impl'
end
M.pString = function(de)
  local c, line, q1, c2 = de.c + 1, de.line
  while true do
    q1, c2 = line:find('\\*"', c)
    if not q1 then de:error[[no matching '"' found]] end
    if (c2 - q1) % 2 == 0 then break end -- len of escapes before quote
    c = c2 + 1
  end
  local s = de:assert(eval(line:sub(de.c, c2)))()
  de.c = c2 + 1
  return s
end
M.pArray = function(de)
  de.c = de.c + 1
  local arr, value, line, c = {}
  while true do
    ::cont::
    de:skipWs(); line, c = de.line, de.c
    if line:find('^,', c) then de.c = de.c + 1; goto cont end
    if line:find('^%]', c) then break end
    push(arr, de())
  end
  de.c = de.c + 1
  return obj
end
M.pObject = function(de)
  de.c = de.c + 1
  local obj, key, value, line, c = {}
  while true do
    ::cont::
    de:skipWs(); line, c = de.line, de.c
    if line:find('^,', c) then de.c = de.c + 1; goto cont end
    if line:find('^}', c) then break end
    key = de(); de:skipWs(); de:consume':'; de:skipWs()
    obj[key] = de()
  end
  de.c = de.c + 1
  return obj
end

-- starting characters indicating what to parse
local DE_FNS = {
  n=M.pNull, t=M.pTrue, f=M.pFalse, ['-'] = M.pNumber,
  ['"']=M.pString, ['{']=M.pObject, ['[']=M.pArray,
}; for c=string.byte'0',string.byte'9' do
  DE_FNS[string.char(c)] = M.pNumber
end

M.De = mty'De' {
  'dat [lines]: lines-like data to parse',
  'null [any]: value to use for null, or leave nil',

  -- mostly internal
  'l [int]', 'c [int]', 'line [string]',
}
getmetatable(M.De).__call = function(T, dat)
  if type(dat) == 'string' then dat = {dat} end
  return mty.construct(T, {dat=dat, l=1, c=1, line=dat[1]})
end

M.De.assert = function(de, ok, msg)
  return ok or error(sfmt('%s.%s: %s', de.l, de.c, msg))
end
M.De.skipWs  = function(de)
  local l, c, line = de.l, de.c, de.line; local len = #line
  while true do
    while c > len do
      l = l + 1; c = 1; line = de.line[l]
      de:assert(line, 'unexpected end of file')
      len = #line
    end
    local c1, c2 = line:find('%s+', de.c)
    if not c1 then break end
    c = c2 + 1
  end
  de.l, de.c, de.line = l, c, line
end
M.De.consume = function(de, pat)
  local line = de.line
  local c1, c2 = line:find(pat, de.c)
  if not c1 then error(sfmt(
    '%s.%s: missing pattern %q', de.l, de.c, pat
  ))end
  c2 = c2 + 1
  if c2 > #line then
    de.l, de.c = de.l + 1, 1
    de.line = de.lines[de.l]
  else de.c = c2 end
  return line:sub(c1, c2)
end
M.De.__call = function(de)
  local len = #de.dat
  while true do
    de:skipWs()
    local l, c = de.l, de.c
    if l > len then return end
    local fn = DE_FNS[de.line:sub(c, c)]
    if not fn then error(sfmt(
      'unrecognized character: %q', de.line:sub(c,c)
    ))end
    return fn(de)
  end
end

return M
