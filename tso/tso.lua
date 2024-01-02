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
M.HEADER = '__tsoh'
M.INVISIBLE_KEY = {[M.HEADER] = "header key"}

M.Ser = mty.record'tso.Ser'
  :field'dat'    :fdoc'output lines'
  :field'attrs'
  :field'line'   :fdoc'current line'
  :field('level', 'number', -1)
  :field('r', 'number', 0) :field('c', 'number', 0)
  :field('ti', 'number', 1)
  :field('needSep',  'boolean', true)
  :field'headers' :field'headersWritten'
M.Ser:new(function(ty_, t)
  t.dat = t.dat or t[1] or {}; t[1] = nil
  t.attrs = t.attrs or {}
  t.line, t.headers, t.headersWritten = {}, {}, {}
  return mty.new(ty_, t)
end)

M.Ser.push = function(ser, s)
  push(ser.line, s)
end
M.Ser.finishLine = function(ser)
  if #ser.line == 0 then return end
  push(ser.dat, concat(ser.line))
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

local function tableHeader(ser, header)
  ser.level = ser.level + 1 -- header is for NEXT level
  ser:finishLine(); ser.needSep = false
  ser:nextValue(); ser.needSep = false; ser:push'#'
  local name = header.name
  if name then ser:nextValue(); ser:push(name) end
  local written = name and ser.headersWritten[name]
  if written then
    mty.assertf(mty.eq(header, written),
      'header name %s differs', name)
  else
    if name then
      if ser.headers[name] then
        mty.assertf(mty.eq(ser.headers[name], header),
          "different headers detected for %q", name)
        ser.headers[name] = header
      end
      ser.headersWritten[name] = header
    end
    for _, h in ipairs(header) do
      assert(type(h) == 'string', 'header must be list of strings')
      ser:string(h)
    end
  end
  ser.level = ser.level - 1
  ser:finishLine(); ser.needSep = false
end

M.Ser.tableEnter = function(ser) ser.level = ser.level + 1 end
M.Ser.tableExit = function(ser)
  ser.level = ser.level - 1
end

M.Ser._tableValues = function(ser, t, ti, headerDone, subHeader)
  for i, v in ipairs(t) do
    ser.ti = ti; ser:any(v, isRows); ti = ti + 1
  end
  local keys = extractKeys(t, len); table.sort(keys)
  for _, k in ipairs(keys) do
    if M.INVISIBLE_KEY[k]               then -- skip
    elseif headerDone and headerDone[k] then -- skip
    else
      ser:nextValue(); ser:push'.'
      ser.ti = ti; ser:_string(k);     ti = ti + 1
      ser.ti = ti; ser:any(t[k], isRows, header); ti = ti + 1
    end
  end
  return ti
end

local function rowValue(ser, v, header, l)
  if type(v) == 'table' then ser:tableRow(v, header)
  elseif header then mty.errorf(
    'All rows must be tables: %q with header %s', v, mty.fmt(header)
  )else
    if l ~= #ser.dat then
      ser:finishLine()
      ser:nextValue(true); ser:push'*'; ser.needSep = false;
      l = #ser.dat
    end
    ser:any(v)
  end
  return l
end
-- table bracketed (i.e. with explicit '{ ... }', can be rows)
M.Ser.table = function(ser, t, header)
  header = header or t[M.HEADER]
  local l = #ser.dat
  ser:tableEnter(); ser:nextValue(); ser:push'{'; ser.needSep = false
  local ti, l = 1, #ser.dat
  if header then tableHeader(ser, header) end
  for i, v in ipairs(t) do
    ser.ti = ti; l = rowValue(ser, v, header, l); ti = ti + 1
  end
  local keys = extractKeys(t, len); table.sort(keys)
  for _, k in ipairs(keys) do
    if M.INVISIBLE_KEY[k]               then -- skip
    else
      ser:nextValue(); ser:push'.'
      ser.ti = ti; ser:_string(k);     ti = ti + 1
      ser.ti = ti; l = rowValue(ser, v, header); ti = ti + 1
    end
  end
  ser:tableExit()
  if l == #ser.dat then ser:nextValue(true) else ser:finishLine() end
  ser:push'}'; ser.needSep = false
end

-- a table row, i.e. a table ended with a newline
M.Ser.tableRow = function(ser, t, header)
  ser:tableEnter(); ser:finishLine()
  local l, ti = #ser.dat, 1
  local headerDone = {}; if header then for _, k in ipairs(header) do
    mty.assertf(not headerDone[k], 'invalid header: multiple %s', k)
    local v = t[k]; mty.assertf(v ~= nil, 'missing header key %s', k)
    ser.ti = ti; ser:any(v); ti = ti + 1
    headerDone[k] = true
  end end
  for i, v in ipairs(t) do
    ser.ti = ti; ser:any(v, isRows); ti = ti + 1
  end
  local keys = extractKeys(t, len); table.sort(keys)
  for _, k in ipairs(keys) do
    if M.INVISIBLE_KEY[k] then -- skip
    elseif headerDone[k]  then -- skip
    else
      ser:nextValue(); ser:push'.'
      ser.ti = ti; ser:_string(k);     ti = ti + 1
      ser.ti = ti; ser:any(t[k], isRows, header); ti = ti + 1
    end
  end
  ser:tableExit()
  ser:finishLine()
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
M.Ser.any = function(ser, v)
  local ty = type(v)
  local fn = mty.assertf(M.SER_TY[ty], 'can not serialize type %s', ty)
  return fn(ser, v)
end
M.Ser.row  = function(ser, row, header)
  assert((#ser.line == 0) and (ser.c == 0) and (ser.level == -1),
    "Ser:row/s must only be called directly at base level")
  mty.assertf(type(row) == 'table',
    'rows must be table of tables (index %s)', ri)
  ser.ti = 1; ser:tableRow(row, header)
  ser:finishLine()
  assert(ser.level == -1, 'internal error: level not reset properly')
end
M.Ser.rows = function(ser, rows, header)
  do local ty = type(rows)
     mty.assertf(ty == 'table', 'rows is table[table], got %s', ty)
  end
  ser.needSep = true
  local header = header or rows[M.HEADER]
  if header then tableHeader(ser, header) end
  for _, row in ipairs(rows) do ser:row(row, header) end
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
  :fieldMaybe'header':fdoc'root header'
  :field'headers':fdoc'named headers'
M.De:new(function(ty_, t)
  t.dat = t.dat or t[1] or {}; t[1] = nil
  assert(t.dat, 'must provide input dat lines')
  t.attrs = t.attrs or {}
  t.line = t.dat[1]
  t.headers = t.headers or {}
  return mty.new(ty_, t)
end)
function M.De.errorf(d, ...)
  error(sfmt('ERROR %s.%s: %s', d.l, d.c, sfmt(...)), 2)
end
function M.De.assertf(d, v, ...) if not v then d:errorf(...) end end
function M.De.pnt(d, ...)
  mty.pnt(sfmt('De.pntf %s.%s:', d.l, d.c), ...)
end

local function deConst(v, msg) return function(d)
  d:assertEnd("invalid %s value", msg); return v
end end

local function deInt(d)
  if d.line:sub(d.c,d.c) == '$' then d.c = d.c + 1 end
  local c1, c2 = d.line:find('%S+', d.c); assert(c1)
  local n = tonumber(d.line:sub(c1, c2), d.attrs.ibase or 10)
  -- TODO: still need to skip whitespace
  d.c = c2 + 1
  return n
end
local function deStr(d)
  local s, c = {}, d.c
  while true do
    local c1, c2 = d.line:find(escPat, d.c)
    push(s, lines.sub(d.dat,
      d.l, c, d.l, (c2 and (c2 - 1)) or #d.line))
    if not c1 then -- no escape in line, look for continuation
      local nxt = d.dat[d.l + 1]
      local c1, c2 = nxt and nxt:find("%s*'")
      if c2 then push(s, '\n'); d.l, d.c = d.l + 1, c2 + 1
      else       d.c = #d.line + 1; break end
    else
      local ch = d.line:sub(c2,c2); d.c = c2 + 1;
      if ch == '\t' then break
      elseif ch == '\\' then -- check for '\t' and '\\'
        ch = escTo[d.line:sub(c2+1,c2+1)]; push(s, ch or '\\')
        if ch then d.c = c2 + 1 end
      else p:error'newline character in line' end
    end
  end
  return table.concat(s)
end

local function deTableVal(d, t, c)
  local v1, v2 = d:getFn(c)(d)
  if v2 then t[v1] = v2 else assert(v1); push(t, v1) end
end

local deTableUnbracketed = nil

local deHeaderName = function(d)
  d:toNext(); if d.line:sub(d.c,d.c) ~= '"' then return deStr(d) end
end
local deHeader = function(d)
  assert(d.line:sub(d.c,d.c) == '#')
  d.c = d.c + 1
  local check = true
  local hname, header = deHeaderName(d); if hname then
    header = deTableUnbracketed(d)
    header.name = hname
    if d.headers[hname] then
      check = false
      mty.assertf((#header == 0) or mty.eq(header, d.headers[hname]),
        "header %q has different values:\nprev: %s\n new: %s",
        hname, mty.fmt(d.headers[name]), mty.fmt(header))
      header = d.headers[hname]
    else d.headers[hname] = header end
  else header = deTableUnbracketed(d) end
  if check then for _, h in ipairs(header) do
    d:assertf(type(h) == 'string', 'header must be only strings')
  end end
  d:nextLine()
  return header
end

local function deTableBracketed(d)
  assert(d.line:sub(d.c,d.c) == '{'); d.c = d.c + 1
  local t, isRow = {}, false
  local ti, header = 0, nil
  ::loop::
  d:toNext(); d:assertf(d.line, "reached EOF, expected closing '}'")
  if d.c > #d.line then
    d:nextLine(); isRow = true
    goto loop
  end
  local ch = d.line:sub(d.c,d.c)
  if ch == '}' then d.c = d.c + 1; goto done end
  if ch == '#' then
    d:assertf(ti == 0 and not header,
      'only single header at top allowed in nested rows')
    header = deHeader(d)
    t[M.HEADER] = header
    goto loop
  end
  if isRow then push(t, deTableUnbracketed(d, header)); isRow = false
  else
    local v1, v2 = d:getFn(ch)(d)
    if v2 then t[v1] = v2 else assert(v1); push(t, v1) end
  end
  ti = ti + 1
  goto loop; ::done::
  return t
end

deTableUnbracketed = function(d, header)
  local t, i, ch, v1, v2 = {}, 1
  ::loop::
  d:toNext()
  if not d.line or d.c > #d.line then goto done end
  ch = d.line:sub(d.c,d.c)
  if ch == '}' then
    if d.c == 1 then goto done end
    d:errorf("found unexpected '}'. Did you mean to use a newline?")
  end
  v1, v2 = d:getFn(ch)(d); if v2 then
    d:assertf(not header or i > #header, 'key %q found before end of header', v1)
    t[v1] = v2
  else d:assertf(v1 ~= nil, 'invalid nil returned')
    if header and i <= #header then t[header[i]] = v1
    else                            push(t, v1) end
  end
  i = i + 1
  goto loop;
  ::done::
  return t
end

local DE_CH = {
  n = deConst(M.none, "n (none)"),
  t = deConst(true,   "t (true)"),
  f = deConst(false,  "f (false)"),
  ['$'] = deInt, -- also 0-9 (see below)
  ['^'] = function(d) error'not impl' end, -- float
  ['"'] = function(d)
    assert(d.line:sub(d.c,d.c) == '"'); d.c = d.c + 1
    return deStr(d)
  end,
  ['.'] = function(d) -- key/value
    assert(d.line:sub(d.c,d.c) == '.'); d.c = d.c + 1
    local k = deStr(d)
    d:toNext(); d:assertf(d.line and d.c <= #d.line,
      '.key must be followed by value')
    return k, d:getFn(d.line:sub(d.c,d.c))(d)
  end,
  ['{'] = deTableBracketed,
  ['@'] = function(d) error'not impl' end,
}

for b=byte'0',byte'9' do DE_CH[char(b)] = deInt end

M.De.nextLine = function(d)
  d.l, d.c = d.l + 1, 1; d.line = d.dat[d.l]
end
M.De.skipWs = function(d)
  while true do
    if not d.line then break end
    while #d.line == 0 do
      d:nextLine(); if not d.line then d:pnt'EOF'; return end
    end
    if d.c > #d.line then -- if EOL check for '+' on next line
      local nxt = d.dat[d.l + 1]
      local c1 = nxt:find'%S'
      if c1 and (nxt:sub(c1,c1) == '+') then
        d:pnt'found + cont'
        d.l, d.c = d.l + 1, c1 + 1
      else break end
    else
      local c1 = d.line:find('[%S\t]', d.c)
      d.c = c1 or (#d.line + 1)
      if d.line:find('^%s*-', d.c) then d.c = #d.line + 1 end
      break
    end
  end
end
M.De.toNext = function(d)
  d:skipWs(); if not d.line then return end
  d.c = (d.line:find('%S', d.c)) or (#d.line + 1)
end
M.De.assertEnd = function(d, fmt, ...)
  local l = d.l; d:skipWs()
  if (d.l > l) or (d.line:sub(d.c,d.c) == '\t') then return end
  local msg = sfmt(fmt, ...)
  error(sfmt('ERROR: %s.%s: %s', d.l, d.c, msg))
end
M.De.getFn = function(d, c)
  local fn = DE_CH[c]; if not fn then
    local o = {}; for k in pairs(DE_CH) do
      push(o, ds.repr(k):sub(2,-2))
    end
    d:errorf('got %q\nExpected one: %s', c, concat(o, ' '))
  end
  return fn
end
M.De.next = function(d, c)
  d:toNext(); if not d.line or d.c > #d.line then return end
  return d:getFn(d.line:sub(d.c,d.c))(d)
end

M.De.__call = function(d)
  d:toNext(); while d.line and d.c > #d.line do d:nextLine() end
  if not d.line then return end
  local ch = d.line and d.line:sub(d.c, d.c)
  if ch == '#' then d.header = deHeader(d) end
  local t = deTableUnbracketed(d, d.header)
  return (next(t) ~= nil) and t or nil
end

return M
