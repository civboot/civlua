local DOC = [[
TSO: Tab Separated Objects

see: Ser (serializer)
     De (deserializer)

README has in-depth documentation.
]]

local pkg = require'pkglib'
local mty = pkg'metaty'
local ds  = pkg'ds'; local lines = ds.lines
local concat, push, sfmt = table.concat, table.insert, string.format
local byte, char = string.byte, string.char

local M = mty.docTy({}, DOC)

local function defaultSpecs(specs)
  if specs and mty.ty(specs) ~= 'table' then
    return specs
  end
  local bm = ds.BiMap{};
  for k, v in pairs(specs or ds.empty) do
    if type(k) == 'number' then       bm[v.__name] = v
    else assert(type(k) == 'string'); bm[k] = v end
  end; return bm
end

local function getSpec(t)
  local mt = getmetatable(t)
  if mt == 'table' then return nil end -- pretend native table
  return mt
end

-- extract keys for serializing
local function extractKeys(t, skip)
  local keys, len = {}, #t
  for k, v in pairs(t) do
    local kty = type(k)
    if kty == 'number' then mty.assertf(
      k <= len, 'nil in list before %s (len=%s)', k, len
    )else
      mty.assertf(kty == 'string',
        'only string keys supported, got %s', kty)
      if not skip[k] then push(keys, k) end
    end
  end
  table.sort(keys)
  return keys
end

local escPat = '[\t\n\\]'
local INF, NEG_INF = 1/0, -1/0
local NAN_STR, INF_STR, NEG_INF = 'nan', 'inf', '-inf'
local IBASE_FMT = {[10] = '%d', [16] = '$%X'}

-- valid escapes (in a string)
-- a '\' will only be serialized as '\\' if it is followed
-- by one of these. Conversly, when deserializing a '\'
-- it is itself unless followed by one of these.
local escTo = { t='\t', ['\\']='\\' }

-----------------
-- Serializer

M.SER_TY = {}

M.ATTR_ASSERTS = {
  ibase = function(b) mty.assertf(IBASE_FMT[b], 'invalid ibase: %q', b) end,
  fbase = function(f) mty.assertf(IBASE_FMT[f], 'invalid fbase: %q', f) end,
}

M.Ser = mty.record2'tso.Ser' {
  'dat: output lines',
  'attrs',
  'specs [BiMap]: bimap of name <--> type',
  '_line[int]: current line',
  '_level[int]',
  '_c  [int]',
  '_ti [int]',
  '_needSep [bool]',
  '_enableAttrs [bool]',
  '_header [table]',
  '_hasRows [bool]',
}; ds.update(M.Ser, {
  _level=-1,     _c=0,              _ti=1,
  _needSep=true, _enableAttrs=true,
})
getmetatable(M.Ser).__call = function(T, t)
  t.dat = t.dat or t[1] or {}; t[1] = nil
  t.attrs, t._line = t.attrs or {}, {}
  t.specs = defaultSpecs(t.specs)
  return mty.construct(T, t)
end

M.Ser._push = function(ser, s)
  assert(type(s) == 'string')
  push(ser._line, s)
end
M.Ser._finishLine = function(ser)
  if #ser._line == 0 then return end
  push(ser.dat, concat(ser._line))
  ser._line = {}; ser._c = 0; ser._needSep = true
end

-- (non-table) values
M.Ser._nextValue = function(ser, skipCont)
  if ser._c == 0 and ser._level > 0 then
    ser:_push(string.rep(' ', ser._level))
  end
  ser._c = ser._c + 1
  if not ser._needSep then -- skip
  elseif ser._c > 1   then ser:_push'\t'
  elseif not skipCont and ser._ti > 1 then ser:_push'+' end
  ser._needSep = true
end

M.Ser._tableEnter = function(ser) ser._level = ser._level + 1 end
M.Ser._tableExit  = function(ser) ser._level = ser._level - 1 end

-- table "rows" contain tables, but are followed by non-tables
M.Ser._tableCont = function(ser)
  ser:_finishLine()
  ser:_nextValue(true); ser:_push'*'; ser._needSep = false;
end

M.Ser.comment = mty.doc[[add line comment]]
(function(ser, c)
  if type(c) ~= 'table' then c = ds.lines(c) end
  ser:_finishLine(); for _, line in ipairs(c) do
    ser:_push'; '; ser:_push(line); ser:_finishLine()
  end
end)

M.Ser.define = mty.doc[[
add spec definition, typically metaty.record
]](function(ser, spec, name)
  name = name or spec.__name
  mty.assertf(not ser.specs[spec],
    'spec %s already registered', spec)
  mty.assertf(not ser.specs[name],
    'different spec named %s already registered', name)
  assert(not ser._hasRows, 'specs must come before rows')
  ser:_finishLine(); ser:_nextValue(); ser:_push'!' ser:_push(name)
  for _, k in ipairs(spec.__fields) do
    mty.assertf(type(k) == 'string',
      'all fields must be a string: %s', k)
    ser:string(k)
  end
  ser:_finishLine(); ser.specs[name] = spec
end)

M.Ser._spec   = function(s, spec)
  local name = mty.assertf(s.specs[spec],
    '%s not a registered spec', spec.__name)
  s:_nextValue(); s:_push':'; s:_push(name)
end

M.Ser._tableKeys = function(ser, t, keys, ti)
  for _, k in ipairs(keys) do
    ser:_finishLine(); ser:_nextValue(); ser:_push'.'
    ser._ti = ti; ser:_string(k);     ti = ti + 1
    ser._ti = ti; l = ser:any(t[k]);  ti = ti + 1
  end
end

-- serialize a row, i.e. table ended by newline
-- header is the current spec, tracked by the parent.
-- We return the header (possibly new)
M.Ser._tableRow = function(ser, t, header)
  ser:_tableEnter(); ser:_finishLine()
  local ti, spec = 1, getSpec(t)
  local specDone = spec and {} or ds.empty
  if spec and (spec ~= header) then
    local name = mty.assertf(ser.specs[spec],
      '%s not a registered spec', spec.__name)
    ser:_nextValue(); ser:_push'#'; ser:_push(name)
    ser:_finishLine()
    header = spec
  end

  if spec then for _, k in ipairs(spec.__fields) do -- serialize spec
    local v = t[k]; mty.assertf(v ~= nil, 'missing spec key %s', k)
    ser._ti = ti; ser:any(v); ti = ti + 1; specDone[k] = true
  end end
  for _, v in ipairs(t) do -- serialize list items
    ser._ti = ti; ser:any(v); ti = ti + 1
  end
  ser:_tableKeys(t, extractKeys(t, specDone), ti)
  ser:_tableExit()
  return header
end

local function rowValue(ser, v, l, header)
  if type(v) == 'table' then header = ser:_tableRow(v, header)
  else
    if l ~= #ser.dat then ser:_tableCont(); l = #ser.dat end
    ser:any(v)
  end
  return l, header
end
M.Ser.table = function(ser, t)
  ser:_tableEnter();
  ser:_nextValue(); ser:_push'{'; ser._needSep = false
  local ti, spec, l, header = 1, getSpec(t), #ser.dat, nil
  local specDone = spec and {} or ds.empty
  if spec then
    ser:_spec(spec)
    for _, k in ipairs(spec.__fields) do -- serialize spec
      local v = t[k]; mty.assertf(v ~= nil, 'missing spec key %s', k)
      ser._ti = ti
      l, header = rowValue(ser, v, l, header)
      ti = ti + 1; specDone[k] = true
    end
  end
  for _, v in ipairs(t) do -- serialize list items
    ser._ti = ti
    l, header = rowValue(ser, v, l, header)
    ti = ti + 1
  end
  local keys = extractKeys(t, specDone)
  if not ds.isEmpty(keys) then
    if l ~= #ser.dat then ser:_tableCont(); l = #ser.dat end
    ser:_tableKeys(t, keys, ti)
  end
  ser:_tableExit()
  if l == #ser.dat then ser:_nextValue(true) else ser:_finishLine() end
  ser:_push'}'; ser._needSep = false
end

M.Ser['nil'] = function(ser)
  error'serializing nil is not permitted. Use none'
end
M.Ser.none   = function(ser) ser:_nextValue(); push(ser._line, 'n') end
M.Ser.boolean = function(ser, b)
  ser:_nextValue(); push(ser._line, b and 't' or 'f')
end
M.Ser.number  = function(ser, n)
  ser:_nextValue()
  if math.type(n) == 'integer' then
    local ibase = ser._enableAttrs and ser.attrs.ibase or 10
    if ibase == 10     then push(ser._line, sfmt('%d', n))
    elseif ibase == 16 then push(ser._line, sfmt('$%X', n))
    else error('invalid ibase: '..ibase) end
  else -- float
    push(ser._line, '^')
    if n ~= n then push(ser._line, 'NaN')
    else
      local fbase = ser._enableAttrs and ser.attrs.fbase or 10
      if     fbase == 10 then push(ser._line, sfmt('%f', n))
      elseif fbase == 16 then
        local f = sfmt('%a', n); if f:sub(1, 2) == '0x' then f = f:sub(3) end
        push(ser._line, f)
      else error('invalid fbase: '..fbase) end
    end
  end
end
M.Ser._string = function(ser, s)
  local i, slen, multiline = 1, #s, false
  while i <= slen do
    local c1 = s:find('[\t\n\\]', i)
    if not c1 then push(ser._line, s:sub(i)); break end
    local ch = s:sub(c1,c1)
    if ch == '\n' then
      multiline = true
      push(ser._line, s:sub(i, c1-1))
      ser:_finishLine(); ser:_nextValue(true)
      push(ser._line, "'")
    elseif ch == '\t' then
      local line = ser._line
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
  ser:_nextValue()
  push(ser._line, '"')
  local multiline = ser:_string(s)
  -- if multiline then ser:cont() end
end
M.Ser.any = function(ser, v)
  local ty = type(v)
  local fn = mty.assertf(M.SER_TY[ty], 'can not serialize type %s', ty)
  return fn(ser, v)
end
M.Ser.row = function(ser, row)
  assert((#ser._line == 0) and (ser._c == 0) and (ser._level == -1),
    "Ser:row/s must only be called directly at base level")
  ser._hasRows = true
  mty.assertf(type(row) == 'table',
    'rows must be table of tables (index %s)', ri)
  ser._ti = 1; ser._header = ser:_tableRow(row, ser._header)
  ser:_finishLine()
  assert(ser._level == -1, 'internal error: level not reset properly')
end
M.Ser.header = function(ser, header)
  if mty.eq(ser._header, header) then return end
  tableHeader(ser, header)
  ser._header = header
end
M.Ser.clearHeader = function(ser)
  ser:_finishLine(); ser:_push'#'; ser:_finishLine()
  ser._header = nil
end
M.Ser.attr = function(ser, key, value)
  mty.assertf(type(key) == 'string', 'attr key must be string')
  local a = M.ATTR_ASSERTS[key]; if a then a(value) end
  ser._enableAttrs = false
  ser.attrs[key] = value
  ser:_finishLine(); ser._needSep = false
  ser:_push'@'; ser:_string(key)
  ser:_nextValue(); ser:any(value)
  ser:_finishLine(); ser._needSep = false
  ser._enableAttrs = nil
end

M.Ser.rows = function(ser, rows)
  for _, row in ipairs(rows) do ser:row(row) end
end

ds.updateKeys(M.SER_TY, M.Ser, {
  'nil', 'none', 'boolean', 'number', 'string', 'table'
})

-----------------
-- Deserializer

M.De = mty.doc[[
De: tso deserializer.
]](mty.record2'tso.De') {
  'dat [table]',
  'attrs [table]',
  'specs [BiMap]: named specs',
  '_line [string]: current line',
  '_l[int]', '_c[int]',
  '_header [root header]',
  '_enableAttrs[bool]',
}; ds.update(M.De, {
  _l = 1, _c = 1, _enableAttrs = true,
})
getmetatable(M.De).__call = function(T, t)
  t.dat = t.dat or t[1] or {}; t[1] = nil
  assert(t.dat, 'must provide input dat lines')
  t.attrs = t.attrs or {}
  t._line = t.dat[1]
  t.specs = defaultSpecs(t.specs)
  return mty.construct(T, t)
end
function M.De._errorf(d, ...)
  error(sfmt('ERROR %s.%s: %s', d._l, d._c, sfmt(...)), 2)
end
function M.De._assertf(d, v, ...)
  if not v then d:_errorf(...) end
  return v
end
function M.De.pnt(d, ...)
  mty.print(sfmt('De.pntf %s.%s:', d._l, d._c), ...)
end

local function deConst(v, msg) return function(d)
  d:_assertEnd("invalid %s value", msg); return v
end end

local function deInt(d)
  if d._line:sub(d._c,d._c) == '$' then d._c = d._c + 1 end
  local c1, c2 = d._line:find('%S+', d._c); assert(c1)
  local n = tonumber(d._line:sub(c1, c2),
    d._enableAttrs and d.attrs.ibase or 10)
  d._c = c2 + 1
  return n
end
local function deStr(d)
  local s, c = {}, d._c
  while true do
    local c1, c2 = d._line:find('[\t\\]', d._c)
    push(s, lines.sub(d.dat,
      d._l, c, d._l, (c2 and (c2 - 1)) or #d._line))
    if not c1 then -- no escape in line, look for continuation
      local nxt = d.dat[d._l + 1]
      local c2 = nxt and select(2, nxt:find"%s*'")
      if c2 then push(s, '\n'); d:_nextLine(); c = c2 + 1; d._c = c
      else       d._c = #d._line + 1; break end
    else
      local ch = d._line:sub(c2,c2); d._c = c2 + 1;
      if ch == '\t' then break
      elseif ch == '\\' then -- check for '\t' and '\\'
        ch = escTo[d._line:sub(c2+1,c2+1)]; push(s, ch or '\\')
        if ch then d._c = c2 + 1 end
      else p:error'newline character in line' end
    end
  end
  return table.concat(s)
end

local deTableUnbracketed = nil

local deHeaderName = function(d)
  if d._line:sub(d._c,d._c) ~= '"' then return deStr(d) end
end

local function deDefine(d)
  assert(d._line:sub(d._c,d._c) == '!'); d._c = d._c + 1
  local name = deStr(d); local fields = deTableUnbracketed(d)
  d:_nextLine()
  if not d.specs[name] then
    local spec = mty.record2('!'..name)(fields)
    getmetatable(spec).tso = true
    print('?? setting spec', name, mty.tostring(spec))
    d.specs[name] = spec
  end
end

local function deSpec(d)
  assert(d._line:sub(d._c,d._c) == ':'); d._c = d._c + 1
  local name = deStr(d); local spec = d.specs[name]
  return d:_assertf(spec, 'field spec %q not specified', name)
end

local deHeader = function(d)
  assert(d._line:sub(d._c,d._c) == '#'); d._c = d._c + 1
  local name = deStr(d)
  return mty.assertf(d.specs[name], 'header spec %s not registered', name)
end

local function deTableValue(d, t, i, ch, spec)
  local v1, v2 = d:_getFn(ch)(d)
  assert(v1 ~= nil, 'invalid nil returned')
  if v2 then
    d:_assertf(not spec or i > #spec.__fields,
      'key %q found before end of header/spec', v1)
    t[v1] = v2
  else d:_assertf(v1 ~= nil, 'invalid nil returned')
    if spec then
      mty.print('?? deTableValue', i, spec, spec.__fields)
    end
    if spec and i <= #spec.__fields then t[spec.__fields[i]] = v1
    else                                 push(t, v1) end
  end
end

local function applySpec(t, spec)
  if not spec then return t end
  return spec(t)
end

local function deTableBracketed(d)
  assert(d._line:sub(d._c,d._c) == '{'); d._c = d._c + 1
  local t, isRow = {}, false
  local ti, header, spec = 0, nil, nil
  ::loop::
  d:toNext(); d:_assertf(d._line, "reached EOF, expected closing '}'")
  if d._c > #d._line then
    d:_nextLine(); isRow = true
    goto loop
  end
  local ch = d._line:sub(d._c,d._c)
  mty.print("?? deTableBracketed", ti, ch, spec)
  if ch == '}' then d._c = d._c + 1;        goto done end
  if ch == '#' then header = deHeader(d); goto loop end
  if ch == ':' then
    d:_assertf(ti == 0 and not spec, 'spec can only appear once at start')
    spec = deSpec(d)
    goto loop
  end
  if ch == '*' then isRow = false; d._c = d._c + 1; goto loop end
  ti = ti + 1
  if isRow then push(t, deTableUnbracketed(d, header)); isRow = false
  else deTableValue(d, t, ti, ch, spec) end
  goto loop; ::done::
  return applySpec(t, spec)
end

deTableUnbracketed = function(d, spec)
  local t, i, ch = {}, 1, nil
  ::loop::
  d:toNext()
  if not d._line or d._c > #d._line then goto done end
  ch = d._line:sub(d._c,d._c)
  if ch == ':' then
    d:_assertf(i == 1, 'header/spec must be at start of table')
    spec = deSpec(d)
    goto loop
  end
  if ch == '}' then
    if d._c == 1 then goto done end
    d:_errorf("found unexpected '}'. Did you mean to use a newline?")
  end
  deTableValue(d, t, i, ch, spec)
  i = i + 1
  goto loop;
  ::done::
  return applySpec(t, spec)
end

local DE_CH = {
  n = deConst(ds.none, "n (none)"),
  t = deConst(true,    "t (true)"),
  f = deConst(false,   "f (false)"),
  ['$'] = deInt, -- also 0-9 (see below)
  ['^'] = function(d) error'not impl' end, -- float
  ['"'] = function(d)
    assert(d._line:sub(d._c,d._c) == '"'); d._c = d._c + 1
    local s = deStr(d)
    return s
  end,
  ['.'] = function(d) -- key/value
    assert(d._line:sub(d._c,d._c) == '.'); d._c = d._c + 1
    local k = deStr(d)
    d:toNext(); d:_assertf(d._line and d._c <= #d._line,
      '.key must be followed by value')
    return k, d:_getFn(d._line:sub(d._c,d._c))(d)
  end,
  ['{'] = deTableBracketed,
  ['@'] = function(d)
    d._c = d._c + 1; local k = deStr(d)
    d:toNext(); d:_assertf(d._line and d._c <= #d._line,
      '@attr must be followed by value')
    d._enableAttrs = false
    local v = d:_getFn(d._line:sub(d._c,d._c))(d)
    d._enableAttrs = nil
    local a = M.ATTR_ASSERTS[k]; if a then a(v) end
    d.attrs[k] = v
  end,
}

for b=byte'0',byte'9' do DE_CH[char(b)] = deInt end
DE_CH['-'] = deInt;

M.De._nextLine = function(d)
  d._l, d._c = d._l + 1, 1; d._line = d.dat[d._l]
end
M.De._skipWs = function(d)
  while true do
    if not d._line then break end
    while #d._line == 0 do d:_nextLine() end
    if d._c > #d._line and d._l < #d.dat then -- if EOL check for '+' on next line
      local nxt = d.dat[d._l + 1]
      local c1,c2 = nxt:find'%s*%+'
      if c2 then
        d:_nextLine(); d._c = c2 + 1
      else break end
    else
      local c1 = d._line:find('[%S\t]', d._c)
      d._c = c1 or (#d._line + 1)
      -- line comment
      if d._line:find('^%s*;', d._c) then d._c = #d._line + 1 end
      break
    end
  end
end
M.De.toNext = function(d)
  d:_skipWs(); if not d._line then return end
  d._c = (d._line:find('%S', d._c)) or (#d._line + 1)
end
M.De._assertEnd = function(d, fmt, ...)
  local l = d._l; d:_skipWs()
  if (d._l > l) or (d._line:sub(d._c,d._c) == '\t') then return end
  local msg = sfmt(fmt, ...)
  error(sfmt('ERROR: %s.%s: %s', d._l, d._c, msg))
end
M.De._getFn = function(d, c)
  local fn = DE_CH[c]; if not fn then
    local o = {}; for k in pairs(DE_CH) do
      push(o, ds.repr(k):sub(2,-2))
    end
    d:_errorf('got %q\nExpected one: %s', c, concat(o, ' '))
  end
  return fn
end

M.De.__call = function(d)
  ::loop::
  d:toNext(); while d._line and d._c > #d._line do d:_nextLine() end
  if not d._line then return end
  d:toNext()
  local ch = d._line and d._line:sub(d._c, d._c)
  if ch == '#' then d._header = deHeader(d); goto loop end
  if ch == '@' then DE_CH['@'](d);          goto loop end
  if ch == '!' then deDefine(d);            goto loop end
  local t = deTableUnbracketed(d, d._header)
  return (next(t) ~= nil) and t or nil
end

M.De.all = mty.doc[[Deserialize all (remaining) rows as a table.]]
(function(d)
  local t = {}; for r in d do push(t, r) end
  return t
end)

return M
