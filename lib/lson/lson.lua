
local M = mod and mod'lson' or {}
local mty = require'metaty'
local fmt = require'fmt'
local ds = require'ds'
local log = require'ds.log'
local pod = require'ds.pod'

local empty = ds.empty
local push, concat = table.insert, table.concat
local sfmt, rep = string.format, string.rep
local sortKeys = fmt.sortKeys
local toPod, fromPod = pod.toPod, pod.fromPod
local Json, Lson, De

--------------------
-- Main Public API

-- Encode lua value to JSON string
M.json = function(v, pretty)
  local enc = pretty and Json:pretty{} or Json{}
  return concat(enc(v))
end

-- Encode lua value to LSON string
M.lson = function(v, pretty)
  local enc = pretty and Lson:pretty{} or Lson{}
  return concat(enc(v))
end

-- Decode JSON/LSON string to lua value
M.decode = function(s) return De(s)() end

------------------
-- JSON Encoder

-- Json Encoder (via metaty.Fmt)
-- This works identically to metaty.Fmt except it overrides
-- how tables are formatted to use JSON instead of printing them.
M.Json = mty.extend(fmt.Fmt, 'Json', {
  'null [any]: value to use for null', null=ds.none,
  'listStart [string]', listStart = '[',
  'listEnd [string]',   listEnd   = ']',
  indexEnd = ',',  keyEnd = ',',
  keySet   = ':',
})
M.Json.pretty = function(E, t)
  t.listStart = t.listStart or '[\n'
  t.listEnd   = t.listEnd   or '\n]'
  t.keySet    = t.keySet    or ': '
  return fmt.Fmt.pretty(E, t)
end

-- note: %q formats ALL newlines with a '\' in front of them
-- it also uses \9 instead of \t for some strange reason, fix that
local CTRL_SUB = {
  ['\\\n'] = '\\n', ['\\9'] = '\\t',
  ['\n'] = true, -- "invalid replacement value" but unreachable
}
M.Json.string = function(enc, s)
  push(enc, (sfmt('%q', s):gsub('\\?[\n9]', CTRL_SUB)))
end
M.Json.table = function(f, t)
  if rawequal(t, f.null) then return push(f, 'null') end
  if f._level >= f.maxIndent then error'max depth reached (recursion?)' end
  local keys = sortKeys(t)
  f:level(1)
  if #keys == 0 then
    if #t > 1 then push(f, f.listStart) else push(f, '[') end
    f:items(t, next(keys)); f:level(-1)
    if #t > 1 then push(f, f.listEnd)   else push(f, ']') end
  else -- has non-list keys
    for i in ipairs(t) do push(keys, i) end
    if #keys > 1 then push(f, f.tableStart) else push(f, '{') end
    f:keyvals(t, keys); f:level(-1)
    if #keys > 1 then push(f, f.tableEnd)   else push(f, '}') end
  end
end
M.Json.__call = function(f, v)
  v = toPod(v)
  f[type(v)](f, v); return f
end
M.Json.tableKey = M.Json.__call

-------------------------------
-- LSON

local ENC_BYTES = {
  ['\n'] = '\\n', ['|'] = [[\|]], ['\\'] = '\\',
  n='n',
}
-- Implementation: basically we need convert newline -> \n
-- and | -> \|. The decoder treats \x (where x is not n or |)
-- as the literal \x, so we also replace \n -> \\n and \| -> \\\|
local function mbytes(backs, esc)
  return rep('\\', #backs * 2)..ENC_BYTES[esc]
end
-- encode as |bytes| instead of "string" for lson
-- You can set Enc.string = lson.bytes for this behavior
M.bytes = function(f, s)
  push(f, '|'); push(f, (s:gsub('(\\*)([\\\n|n])', mbytes))); push(f, '|')
end

-- Similar to JSOn but no commas and strings are encoded as |bytes|
M.Lson = mty.extend(M.Json, 'Lson', {
  indexEnd = ' ', keyEnd=' ',
})
M.Lson.string = M.bytes
M.Lson.pretty = function(E, t)
  t.listStart = t.listStart or '[\n'
  t.listEnd   = t.listEnd   or '\n]'
  t.indexEnd  = t.indexEnd  or '\n'
  t.keyEnd    = t.keyEnd    or '\n'
  t.keySet    = t.keySet    or ': '
  return fmt.Fmt.pretty(E, t)
end

-------------------------------
-- Decoder
local eval = function(s) return load('return '..s, nil, 't', empty) end

M.deNull  = function(de) de:consume'^null';  return de.null end
M.deTrue  = function(de) de:consume'^true';  return true    end
M.deFalse = function(de) de:consume'^false'; return false   end
M.deNumber = function(de)
  local str = de:consume'^[^%s:,%]}]+'
  local n = de:assert(eval(str))()
  assert(type(n) == 'number')
  return n
end
M.deString = function(de)
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
local DE_BYTES = {
  ['\\\n'] = '\\\n', ['\\n'] = '\n',
  ['\\|']  = '|',    ['\\']  = '\\', ['\\\\'] = '\\',
}
M.deBytes = function(de) -- |binary data|
  local b, l, c, line = {}, de.l, de.c + 1, de.line
  local c1, c2 = c
  while true do
    while c <= #line do
      c1, c2 = line:find('\\*|', c1); if c1 then
        if (c2 - c1) % 2 == 0 then
          push(b, line:sub(c, c2-1))
          c = c2 + 1
          goto done
        else c1 = c2 + 1 end
      else break end -- no | detected, next line
    end
    push(b, line:sub(c)); push(b, '\n')
    l, c = d.l + 1, 1
    line = d.dat[l]; if not line then error(sfmt(
      "%s.%s: '|' never closed (reached EOF)", de.l, de.c
    ))end
  end
  ::done::
  de.l, de.c, de.line = l, c, line
  return concat(b):gsub('\\[\nn|\\]?', DE_BYTES)
end
M.deArray = function(de)
  de.c = de.c + 1
  local arr, value, line, c = {}
  while true do
    ::cont::
    de:skipWs(); line, c = de.line, de.c
    if line:find('^%]', c) then break end
    push(arr, de())
  end
  de.c = de.c + 1
  return arr
end
M.deObject = function(de)
  de.c = de.c + 1
  local obj, key, val, line, c = {}
  while true do
    ::cont::
    de:skipWs(); line, c = de.line, de.c
    if line:find('^,', c) then de.c = de.c + 1; goto cont end
    if line:find('^}', c) then break end
    key = de(); de:assert(key ~= nil, 'expected key')
    de:skipWs(); de:consume'^:'; de:skipWs()
    val = de(); de:assert(val ~= nil, 'expected value')
    obj[key] = val
  end
  de.c = de.c + 1
  return obj
end

-- starting characters indicating what to parse
local DE_FNS = {
  n=M.deNull, t=M.deTrue, f=M.deFalse, ['-'] = M.deNumber,
  ['"']=M.deString, ['|']=M.deBytes,
  ['{']=M.deObject, ['[']=M.deArray,
}; for c=string.byte'0',string.byte'9' do
  DE_FNS[string.char(c)] = M.deNumber
end

-- De(string or lines) -> value-iter
-- for val in De'["my", "lson"]' do ... end
M.De = mty'De' {
  'dat [lines]: lines-like data to parse',
  'null [any]: value to use for null', null=ds.none,

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
M.De.skipWs  = function(de, eofOkay)
  local l, c, line, dat = de.l, de.c, de.line, de.dat
  while true do
    while c > #line do
      l, c, line = l+1, 1, dat[l+1]
      if not line then
        de:assert(eofOkay, 'unexpected end of file')
        goto done
      end
    end
    c = line:find('[^%s,]', c); if c then break end
    l, c, line = l + 1, 1, dat[l+1]
  end
  ::done::
  de.l, de.c, de.line = l, c, line
end
-- consume the pattern returning the consumed string
M.De.consume = function(de, pat, context)
  local line = de.line
  local c1, c2 = line:find(pat, de.c)
  if not c1 then error(sfmt(
    '%s.%s: missing %s %q', de.l, de.c,
    context or 'pattern', pat:gsub('[%^%%]', '')
  ))end
  de.c = c2 + 1
  return line:sub(c1, c2)
end
M.De.__call = function(de)
  de:skipWs(true)
  local l, c = de.l, de.c
  if l > #de.dat then return end
  local fn = DE_FNS[de.line:sub(c, c)] or error(sfmt(
    'unrecognized character: %q', de.line:sub(c,c)))
  return fromPod(fn(de))
end

Json, Lson, De = M.Json, M.Lson, M.De -- locals
return M
