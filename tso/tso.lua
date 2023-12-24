local mty = require'metaty'
local ds  = require'ds'; local lines = ds.lines
local concat, push, sfmt = table.concat, table.insert, string.format
local byte, char = string.byte, string.char

local function onlyNonTable(t)
  local fst = next(t); local scnd = next(t, fst)
  if scnd then return end
  return type(fst) ~= 'table' and fst or nil
end

local function extractKeys(t)
  local keys, len = {}, #t
  for k, v in pairs(t) do
    local kty = type(k)
    if kty == 'number' then mty.assertf(
      k <= len, 'nil in list at %s (len=%s)', k, len
    )else
      mty.assertf(kty == 'string',
        'only string keys supported, got %s', kty)
      push(keys, k)
    end
  end
  return keys
end

local M = mty.docTy({}, [[
TSO: Tab Separated Objects

See README for in-depth documentation.
]])

M.none = ds.none
M.SER_TY = {}

local escPat = '[\t\\]'
local INF, NEG_INF = 1/0, -1/0
local NAN_STR, INF_STR, NEG_INF = 'nan', 'inf', '-inf'

-- valid escapes (in a string)
-- a '\' will only be serialized as '\\' if it is followed
-- by one of these. Conversly, when deserializing a '\'
-- it is itself unless followed by one of these.
local escTo = { t='\t', ['\\']='\\' }

-----------------
-- Serializer

M.SER_TY = {}

M.Ser = mty.record'tso.Ser'
  :field'dat'    :fdoc'output lines'
  :field'attrs'
  :field'line'   :fdoc'current line'
  :field('level', 'number', -1)
  :field('r', 'number', 0) :field('c', 'number', 0)
  :field('ti', 'number', 1)
  :field('needSep',  'boolean', true)
M.Ser:new(function(ty_, t)
  t.dat = t.dat or t[1] or {}; t[1] = nil
  t.attrs = t.attrs or {}
  t.line = {};
  return mty.new(ty_, t)
end)

M.Ser.push = function(ser, s)
  mty.pntf('?? ser push: %q', s)
  push(ser.line, s)
end
M.Ser.finishLine = function(ser)
  if #ser.line == 0 then return end
  push(ser.dat, concat(ser.line))
  mty.pntf('?? ser line: %q', concat(ser.line))
  ser.line = {}; ser.c = 0; ser.needSep = true
end

-- (non-table) values
M.Ser.nextValue = function(ser, skipCont)
  if ser.c == 0 and ser.level > 0 then
    ser:push(string.rep(' ', ser.level))
  end
  ser.c = ser.c + 1
  if not ser.needSep then -- skip
  elseif ser.c > 1   then ser:push'\t'
  elseif not skipCont and ser.ti > 1 then ser:push'+' end
  ser.needSep = true
end

M.Ser.tableEnter = function(ser, bracket)
  ser.level = ser.level + 1
  if bracket then
    ser:nextValue(); ser:push'{'; ser.needSep = false
  else
    ser:finishLine()
  end
end
M.Ser.tableExit = function(ser, bracket)
  ser.level = ser.level - 1
  if bracket then
    ser:nextValue(true); ser:push'}'; ser.needSep = false
  else ser:finishLine() end
end

M.Ser.table = function(ser, t, pBracket)
  -- can skip bracket (use newline) if parent has bracket
  local bracket = not pBracket
  mty.pntf('?? table c=%s ti=%s pBracket=%s bracket=%s: %s',
    ser.c, ser.ti, pBracket, bracket, mty.fmt(t))
  ser:tableEnter(bracket)
  local ti = 1
  for i, v in ipairs(t) do
    mty.pnt('?? _row i='..i..' v:', v)
    ser.ti = ti; ser:any(v, bracket); ti = ti + 1
  end
  local keys = extractKeys(t, len); table.sort(keys)
  for _, k in ipairs(keys) do
    ser:nextValue(); ser:push'.'
    ser.ti = ti; ser:_string(k);     ti = ti + 1
    ser.ti = ti; ser:any(t[k], bracket); ti = ti + 1
  end
  ser:tableExit(bracket)
end
M.Ser['nil'] = function(ser) ser:error'serializing nil is not permitted. Use none' end
M.Ser.none   = function(ser) ser:nextValue(); push(ser.line, 'n') end
M.Ser.boolean = function(ser, b)
  ser:nextValue(); push(ser.line, b and 't' or 'f')
end
M.Ser.number  = function(ser, n)
  ser:nextValue()
  if n == math.floor(n) then -- integer
    local ibase = ser.attrs.ibase or 10
    if ibase == 10     then push(ser.line, sfmt('%d', n))
    elseif ibase == 16 then push(ser.line, sfmt('$%X', n))
    else error('invalid ibase: '..ibase) end
  else -- float
    push(ser.line, '^')
    if n ~= n then push(ser.line, 'NaN')
    else
      local fbase = ser.attrs.fbase or 10
      if     fbase == 10 then push(ser.line, sfmt('%f', n))
      elseif fbase == 16 then
        local f = sfmt('%a', n); if f:sub(1, 2) == '0x' then f = f:sub(3) end
        push(ser.line, f)
      else error('invalid fbase: '..fbase) end
    end
  end
end
M.Ser._string = function(ser, s)
  local i, slen, multiline = 1, #s, false
  while i <= slen do
    local c1 = s:find(escPat, i)
    if not c1 then push(ser.line, s:sub(i)); break end
    local ch = f:sub(c1,c1)
    if ch == '\n' then
      multiline = true
      push(ser.line, s:sub(i, c1-1))
      ser:finishLine(); ser:nextValue()
      push(ser.line, "'")
    elseif ch == '\t' then
      local line = ser.line
      push(line, s:sub(i, c1-1)); push(line, [[\t]])
      if ch == '\\' then
        push(line, s:sub(i, c1))
        if escTo[s:sub(i, c1+1)] then push(line, '\\') end
      end
    end
    i = c1 + 1
  end
  return multiline
end
M.Ser.string = function(ser, s)
  ser:nextValue()
  push(ser.line, '"')
  local multiline = ser:_string(s)
  if multiline then ser:cont() end
end
M.Ser.any = function(ser, v, ...)
  local ty = type(v)
  local fn = mty.assertf(M.SER_TY[ty], 'can not serialize type %s', ty)
  return fn(ser, v, ...)
end
M.Ser.row  = function(ser, row)
  assert((#ser.line == 0) and (ser.c == 0) and (ser.level == -1),
    "Ser:row/s must only be called directly at base level")
  mty.assertf(type(row) == 'table',
    'rows must be table of tables (index %s)', ri)
  ser.ti = 1; ser:table(row, true)
  ser:finishLine()
  assert(ser.level == -1, 'internal error: level not reset properly')
end
M.Ser.rows = function(ser, rows)
  do local ty = type(rows)
     mty.assertf(ty == 'table', 'rows is table[table], got %s', ty)
  end
  ser.needSep = true
  for _, row in ipairs(rows) do ser:row(row) end
end

ds.updateKeys(M.SER_TY, M.Ser, {
  'nil', 'none', 'boolean', 'number', 'string', 'table'
})

-----------------
-- Deserializer

M.De = mty.doc[[
De: tso deserializer.
]](mty.record'tso.De')
  :field'dat':fdoc'input lines'
  :field'attrs'
  :fieldMaybe('line', 'string'):fdoc'current line'
  :field('l', 'number', 1) :field('c', 'number', 1)
  :field('level', 'number', -1)
M.De:new(function(ty_, t)
  t.dat = t.dat or t[1] or {}; t[1] = nil
  assert(t.dat, 'must provide input dat lines')
  t.attrs = t.attrs or {}
  t.line = t.dat[1]
  return mty.new(ty_, t)
end)
function M.De.errorf(d, ...)
  error(sfmt('ERROR %s.%s: ', d.l, d.c, sfmt(...)), 2)
end
function M.De.assertf(d, v, ...) if not v then d:errorf(...) end end
function M.De.pnt(d, ...)
  mty.pnt(sfmt('De.pntf %s.%s:', d.l, d.c), ...)
end

local function deConst(v, msg) return function(d)
  d:assertEnd("invalid %s value", msg); return v
end end

local function deInt(d)
  d:pnt('deInt', d.line:sub(d.c))
  if d.line:sub(d.c,d.c) == '$' then d.c = d.c + 1 end
  local c1, c2 = d.line:find('%S+', d.c); assert(c1)
  local n = tonumber(d.line:sub(c1, c2), d.attrs.ibase or 10)
  -- TODO: still need to skip whitespace
  d.c = c2 + 1
  return n
end
local function deStr(d)
  d:pnt('deStr start:', d.line:sub(d.c))
  assert(d.line:sub(d.c,d.c) == '"')
  d.c = d.c + 1
  local s, c = {}, d.c
  while true do
    local c1, c2 = d.line:find(escPat, d.c)
    d:pnt('?? str loop', c1, c2)
    push(s, lines.sub(d.dat,
      d.l, c, d.l, (c2 and (c2 - 1)) or #d.line))
    if not c1 then -- no escape in line
      local line = d.line; d:nextLine(); d:skipWs()
      if d.line and ("'" == d.line:sub(d.c,d.c)) then
        -- line continuation
        push(s, '\n')
        l, c, d.c = d.l, d.c + 1, d.c + 1
      else break end
    else
      local ch = d.line:sub(c2,c2); d.c = c2 + 1;
      if ch == '\t' then break
      elseif ch == '\\' then -- check for '\t' and '\\'
        ch = escTo[d.line:sub(c2+1,c2+1)]; push(s, ch or '\\')
        if ch then d.c = c2 + 2 end
      else p:error'newline character in line' end
    end
  end
  d:pnt('deStr got:', table.concat(s))
  return table.concat(s)
end

local function deTableVal(d, t, c)
  local v1, v2 = d:getFn(c)(d)
  d:pnt('table Val', v1, v2)
  if v2 then t[v1] = v2 else assert(v1); push(t, v1) end
end

local deTableUnbracketed = nil

local function deTableBracketed(d)
  assert(d.line:sub(d.c,d.c) == '{'); d.c = d.c + 1
  local t, isRow = {}, false
  ::loop::
  d:toNext();
  d:pnt(sfmt('tableBrack loop isRow=%s: %s', isRow, ds.repr(d.line:sub(d.c))))
  d:assertf(d.line, "reached EOF, expected closing '}'")
  if d.c > #d.line then
    d:nextLine(); isRow = true
    goto loop
  end

  local c = d.line:sub(d.c,d.c)
  if c == '}' then d.c = d.c + 1; goto done end
  if isRow then push(t, deTableUnbracketed(d))
  else          deTableVal(d, t, c) end
  isRow = false
  goto loop; ::done::
  d:pnt('tableBrack return', t)
  return t
end

deTableUnbracketed = function(d)
  local t, i, ch = {}, 1
  ::loop::
  d:pnt('tableUnb loop', ds.repr(d.line:sub(d.c)))
  d:toNext()
  if not d.line or d.c > #d.line then goto done end
  ch = d.line:sub(d.c,d.c)
  if ch == '}' then
    if d.c == 1 then goto done end
    d:errorf("found unexpected '}'. Did you mean to use a newline?")
  end
  deTableVal(d, t, ch);
  d:pnt('tableUnb end i='..i, ds.repr(d.line:sub(d.c)))
  i = i + 1
  goto loop;
  ::done::
  d:pnt('tableUnb return', t)
  return t
end

local DE_CH = {
  n = deConst(M.none, "n (none)"),
  t = deConst(true,   "t (true)"),
  f = deConst(false,  "f (false)"),
  ['$'] = deInt, -- also 0-9 (see below)
  ['^'] = function(d) error'not impl' end, -- float
  ['"'] = deStr,
  ['.'] = function(d) local k = deStr(d); return k, d() end,
  ['{'] = deTableBracketed,
  ['@'] = function(d) error'not impl' end,
}

for b=byte'0',byte'9' do DE_CH[char(b)] = deInt end

M.De.nextLine = function(d)
  d.l, d.c = d.l + 1, 1; d.line = d.dat[d.l]
end
M.De.skipWs = function(d)
  while true do
    d:pnt('skipWs start:', d.line:sub(d.c))
    if not d.line then break end
    while #d.line == 0 do
      d:nextLine(); if not d.line then d:pnt'EOF'; return end
    end
    if d.c > #d.line then -- if EOL check for '+' on next line
      d:pnt'skipWs EoL'
      local nxt = d.dat[d.l + 1]; local c1 = nxt:find'%S'
      if c1 and (nxt:sub(c1,c1) == '+') then
        d.l, d.c = d.l + 1, c1 + 1
      else break end
    else
      local c1 = d.line:find('[%S\t]', d.c)
      d.c = c1 or (#d.line + 1)
      -- check for line comment
      if d.line:find('%s*-', d.c) then d:nextLine()
      else break end
    end
  end
  d:pnt('skipWs done:', d.line:sub(d.c))
end
M.De.toNext = function(d)
  d:skipWs(); if not d.line then return end
  d.c = d.line:find('%S', d.c) or (#d.line + 1)
end
M.De.assertEnd = function(d, fmt, ...)
  local l = d.l; d:skipWs()
  if (d.l > l) or (d.line:sub(d.c,d.c) == '\t') then return end
  local msg = sfmt(fmt, ...)
  error(sfmt('ERROR: %s.%s: %s', d.l, d.c, msg))
end
M.De.getFn = function(d, c)
  local fn = DE_CH[c]; if not fn then
    local o = {}; for k in pairs(DE_CH) do push(o, ds.repr(k)) end
    d:errorf('got %q\nExpected: %s', d.l, d.c, c, concat(o, ' '))
  end
  return fn
end
M.De.__call = function(d)
  local t = deTableUnbracketed(d)
  return (next(t) ~= nil) and t or nil
end

return M
