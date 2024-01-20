-- FIXME: use "define" instead of "spec" for defining
--        types.
local pkg = require'pkg'
local mty = pkg'metaty'
local ds  = pkg'ds'; local lines = ds.lines
local concat, push, sfmt = table.concat, table.insert, string.format
local byte, char = string.byte, string.char

local function onlyNonTable(t)
  local fst = next(t); local scnd = next(t, fst)
  if scnd then return end
  return type(fst) ~= 'table' and fst or nil
end

local function defaultSpecs(specs)
  specs = specs or {}
  if not getmetatable(specs) then
    specs = ds.BiMap(specs)
  end
  return specs
end

local function getSpec(t)
  local mt = getmetatable(t)
  if mt == 'table' then return nil end -- pretend native table
  return mt
end

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

local M = mty.docTy({}, [[
TSO: Tab Separated Objects

See README for in-depth documentation.
]])

M.none = ds.none
M.SER_TY = {}

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
M.SPEC  = '__spec'
M.SPECH = '__spech'
M.INVISIBLE_KEY = {[M.SPEC] = "field spec", [M.SPECH] = "field header spec"}

M.ATTR_ASSERTS = {
  ibase = function(b) mty.assertf(IBASE_FMT[b], 'invalid ibase: %q', b) end,
  fbase = function(f) mty.assertf(IBASE_FMT[f], 'invalid fbase: %q', f) end,
}

M.Ser = mty.record'tso.Ser'
  :field'dat'    :fdoc'output lines'
  :field'attrs'
  :field('specs', ds.BiMap):fdoc'bimap of name <--> type'
  :field'line'   :fdoc'current line'
  :field('level', 'number', -1)
  :field('r', 'number', 0) :field('c', 'number', 0)
  :field('ti', 'number', 1)
  :field('needSep',  'boolean', true)
  :field('enableAttrs', 'boolean', true)
  :fieldMaybe'_header' -- current root header
  :fieldMaybe('_hasRows', 'boolean')
M.Ser:new(function(ty_, t)
  t.dat = t.dat or t[1] or {}; t[1] = nil
  t.attrs, t.line = t.attrs or {}, {}
  t.specs = defaultSpecs(t.specs)
  return mty.new(ty_, t)
end)

M.Ser.push = function(ser, s)
  assert(type(s) == 'string')
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

M.Ser.tableEnter = function(ser) ser.level = ser.level + 1 end
M.Ser.tableExit  = function(ser) ser.level = ser.level - 1 end

-- table "rows" contain tables, but are followed by non-tables
M.Ser._tableCont = function(ser)
  ser:finishLine()
  ser:nextValue(true); ser:push'*'; ser.needSep = false;
end

M.Ser.spec = function(ser, spec)
  mty.assertf(not ser.specs[spec],
    'spec %s already registered', spec)
  mty.assertf(not ser.specs[spec.__name],
    'different spec named %s already registered', spec.__name)
  assert(not ser._hasRows, 'specs must come before rows')
  ser:finishLine(); ser:nextValue(); ser:push'!' ser:push(spec.__name)
  for _, k in ipairs(spec.__fields) do
    mty.assertf(type(k) == 'string',
      'all fields must be a string: %s', k)
    ser:string(k)
  end
  ser:finishLine(); ser.specs[spec.__name] = spec
end

local function serHeader(s, spec)
  local name = mty.assertf(s.specs[spec],
    '%s not a registered spec', spec.__name)
  s:nextValue(); s:push'#'; s:push(name)
  s:finishLine()
end
M.Ser._spec   = function(s, spec)
  local name = mty.assertf(s.specs[spec],
    '%s not a registered spec', spec.__name)
  s:nextValue(); s:push':'; s:push(name)
end

M.Ser._tableKeys = function(ser, t, keys, ti)
  for _, k in ipairs(keys) do
    ser:finishLine(); ser:nextValue(); ser:push'.'
    ser.ti = ti; ser:_string(k);     ti = ti + 1
    ser.ti = ti; l = ser:any(t[k]);  ti = ti + 1
  end
end

-- serialize a row, i.e. table ended by newline
-- header is the current spec, tracked by the parent.
-- We return the header (possibly new)
M.Ser.tableRow = function(ser, t, header)
  ser:tableEnter(); ser:finishLine()
  local ti, spec = 1, getSpec(t)
  local specDone = spec and {} or ds.empty
  if spec and (spec ~= header) then serHeader(ser, spec); header = spec end
  if spec then for _, k in ipairs(spec.__fields) do -- serialize spec
    local v = t[k]; mty.assertf(v ~= nil, 'missing spec key %s', k)
    ser.ti = ti; ser:any(v); ti = ti + 1; specDone[k] = true
  end end
  for _, v in ipairs(t) do -- serialize list items
    ser.ti = ti; ser:any(v); ti = ti + 1
  end
  ser:_tableKeys(t, extractKeys(t, specDone), ti)
  ser:tableExit()
  return header
end

local function rowValue(ser, v, l, header)
  if type(v) == 'table' then header = ser:tableRow(v, header)
  else
    if l ~= #ser.dat then ser:_tableCont(); l = #ser.dat end
    ser:any(v)
  end
  return l, header
end

M.Ser.table = function(ser, t)
  ser:tableEnter();
  ser:nextValue(); ser:push'{'; ser.needSep = false
  local ti, spec, l, header = 1, getSpec(t), #ser.dat, nil
  local specDone = spec and {} or ds.empty
  if spec then
    ser:_spec(spec)
    for _, k in ipairs(spec.__fields) do -- serialize spec
      local v = t[k]; mty.assertf(v ~= nil, 'missing spec key %s', k)
      ser.ti = ti
      l, header = rowValue(ser, v, l, header)
      ti = ti + 1; specDone[k] = true
    end
  end
  for _, v in ipairs(t) do -- serialize list items
    ser.ti = ti
    l, header = rowValue(ser, v, l, header)
    ti = ti + 1
  end
  local keys = extractKeys(t, specDone)
  if not ds.isEmpty(keys) then
    if l ~= #ser.dat then ser:_tableCont(); l = #ser.dat end
    ser:_tableKeys(t, keys, ti)
  end
  ser:tableExit()
  if l == #ser.dat then ser:nextValue(true) else ser:finishLine() end
  ser:push'}'; ser.needSep = false
end

M.Ser['nil'] = function(ser) error'serializing nil is not permitted. Use none' end
M.Ser.none   = function(ser) ser:nextValue(); push(ser.line, 'n') end
M.Ser.boolean = function(ser, b)
  ser:nextValue(); push(ser.line, b and 't' or 'f')
end
M.Ser.number  = function(ser, n)
  ser:nextValue()
  if math.type(n) == 'integer' then
    local ibase = ser.enableAttrs and ser.attrs.ibase or 10
    if ibase == 10     then push(ser.line, sfmt('%d', n))
    elseif ibase == 16 then push(ser.line, sfmt('$%X', n))
    else error('invalid ibase: '..ibase) end
  else -- float
    push(ser.line, '^')
    if n ~= n then push(ser.line, 'NaN')
    else
      local fbase = ser.enableAttrs and ser.attrs.fbase or 10
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
    local c1 = s:find('[\t\n\\]', i)
    if not c1 then push(ser.line, s:sub(i)); break end
    local ch = s:sub(c1,c1)
    if ch == '\n' then
      multiline = true
      push(ser.line, s:sub(i, c1-1))
      ser:finishLine(); ser:nextValue(true)
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
  -- if multiline then ser:cont() end
end
M.Ser.any = function(ser, v)
  local ty = type(v)
  local fn = mty.assertf(M.SER_TY[ty], 'can not serialize type %s', ty)
  return fn(ser, v)
end
M.Ser.row = function(ser, row)
  assert((#ser.line == 0) and (ser.c == 0) and (ser.level == -1),
    "Ser:row/s must only be called directly at base level")
  ser._hasRows = true
  mty.assertf(type(row) == 'table',
    'rows must be table of tables (index %s)', ri)
  ser.ti = 1; ser._header = ser:tableRow(row, ser._header)
  ser:finishLine()
  assert(ser.level == -1, 'internal error: level not reset properly')
end
M.Ser.header = function(ser, header)
  if mty.eq(ser._header, header) then return end
  tableHeader(ser, header)
  ser._header = header
end
M.Ser.clearHeader = function(ser)
  ser:finishLine(); ser:push'#'; ser:finishLine()
  ser._header = nil
end
M.Ser.attr = function(ser, key, value)
  mty.assertf(type(key) == 'string', 'attr key must be string')
  local a = M.ATTR_ASSERTS[key]; if a then a(value) end
  ser.enableAttrs = false
  ser.attrs[key] = value
  ser:finishLine(); ser.needSep = false
  ser:push'@'; ser:_string(key)
  ser:nextValue(); ser:any(value)
  ser:finishLine(); ser.needSep = false
  ser.enableAttrs = nil
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
]](mty.record'tso.De')
  :field'dat':fdoc'input lines'
  :field'attrs'
  :field('specs', ds.BiMap):fdoc'named specs'
  :fieldMaybe('line', 'string'):fdoc'current line'
  :field('l', 'number', 1) :field('c', 'number', 1)
  :field('level', 'number', -1)
  :fieldMaybe'header':fdoc'root header'
  :field('enableAttrs', 'boolean', true)
M.De:new(function(ty_, t)
  t.dat = t.dat or t[1] or {}; t[1] = nil
  assert(t.dat, 'must provide input dat lines')
  t.attrs = t.attrs or {}
  t.line = t.dat[1]
  t.specs = defaultSpecs(t.specs)
  return mty.new(ty_, t)
end)
function M.De.errorf(d, ...)
  error(sfmt('ERROR %s.%s: %s', d.l, d.c, sfmt(...)), 2)
end
function M.De.assertf(d, v, ...) if not v then d:errorf(...) end; return v end
function M.De.pnt(d, ...)
  mty.pnt(sfmt('De.pntf %s.%s:', d.l, d.c), ...)
end

local function deConst(v, msg) return function(d)
  d:assertEnd("invalid %s value", msg); return v
end end

local function deInt(d)
  if d.line:sub(d.c,d.c) == '$' then d.c = d.c + 1 end
  local c1, c2 = d.line:find('%S+', d.c); assert(c1)
  local n = tonumber(d.line:sub(c1, c2),
    d.enableAttrs and d.attrs.ibase or 10)
  d.c = c2 + 1
  return n
end
local function deStr(d)
  local s, c = {}, d.c
  while true do
    local c1, c2 = d.line:find('[\t\\]', d.c)
    push(s, lines.sub(d.dat,
      d.l, c, d.l, (c2 and (c2 - 1)) or #d.line))
    if not c1 then -- no escape in line, look for continuation
      local nxt = d.dat[d.l + 1]
      local c2 = nxt and select(2, nxt:find"%s*'")
      if c2 then push(s, '\n'); d:nextLine(); c = c2 + 1; d.c = c
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

local deTableUnbracketed = nil

local deHeaderName = function(d)
  if d.line:sub(d.c,d.c) ~= '"' then return deStr(d) end
end

local function deDefine(d)
  assert(d.line:sub(d.c,d.c) == '!'); d.c = d.c + 1
  local name = deStr(d); local fields = deTableUnbracketed(d)
  d:nextLine()
  -- TODO: store fields for assertion
  mty.assertf(
    d.specs[name],
    'unrecognized spec %s', name)
end

local function deSpec(d)
  assert(d.line:sub(d.c,d.c) == ':'); d.c = d.c + 1
  local name = deStr(d)
  return d:assertf(d.specs[name], 'field spec %q not specified', name)
end

local deHeader = function(d)
  assert(d.line:sub(d.c,d.c) == '#'); d.c = d.c + 1
  local name = deStr(d)
  return mty.assertf(d.specs[name], 'header spec %s not registered', name)
end

local function deTableValue(d, t, i, ch, spec)
  local v1, v2 = d:getFn(ch)(d)
  assert(v1 ~= nil, 'invalid nil returned')
  if v2 then
    d:assertf(not spec or i > #spec.__fields,
      'key %q found before end of header/spec', v1)
    t[v1] = v2
  else d:assertf(v1 ~= nil, 'invalid nil returned')
    if spec and i <= #spec.__fields then t[spec.__fields[i]] = v1
    else                                 push(t, v1) end
  end
end

local function deSpec(t, spec)
  if not spec then return t end
  return spec(t)
end

local function deTableBracketed(d)
  assert(d.line:sub(d.c,d.c) == '{'); d.c = d.c + 1
  local t, isRow = {}, false
  local ti, header, spec = 0, nil, nil
  ::loop::
  d:toNext(); d:assertf(d.line, "reached EOF, expected closing '}'")
  if d.c > #d.line then
    d:nextLine(); isRow = true
    goto loop
  end
  local ch = d.line:sub(d.c,d.c)
  if ch == '}' then d.c = d.c + 1;        goto done end
  if ch == '#' then header = deHeader(d); goto loop end
  if ch == ':' then
    d:assertf(ti == 0 and not spec, 'spec can only appear once at start')
    spec = deSpec(d)
    goto loop
  end
  if ch == '*' then isRow = false; d.c = d.c + 1; goto loop end
  if isRow then push(t, deTableUnbracketed(d, header)); isRow = false
  else deTableValue(d, t, ti, ch, spec) end
  ti = ti + 1
  goto loop; ::done::
  return deSpec(t, spec)
end

deTableUnbracketed = function(d, spec)
  local t, i, ch = {}, 1, nil
  ::loop::
  d:toNext()
  if not d.line or d.c > #d.line then goto done end
  ch = d.line:sub(d.c,d.c)
  if ch == ':' then
    d:assertf(i == 1, 'header/spec must be at start of table')
    spec = deSpec(d)
    goto loop
  end
  if ch == '}' then
    if d.c == 1 then goto done end
    d:errorf("found unexpected '}'. Did you mean to use a newline?")
  end
  deTableValue(d, t, i, ch, spec)
  i = i + 1
  goto loop;
  ::done::
  return deSpec(t, spec)
end

local DE_CH = {
  n = deConst(M.none, "n (none)"),
  t = deConst(true,   "t (true)"),
  f = deConst(false,  "f (false)"),
  ['$'] = deInt, -- also 0-9 (see below)
  ['^'] = function(d) error'not impl' end, -- float
  ['"'] = function(d)
    assert(d.line:sub(d.c,d.c) == '"'); d.c = d.c + 1
    local s = deStr(d)
    return s
  end,
  ['.'] = function(d) -- key/value
    assert(d.line:sub(d.c,d.c) == '.'); d.c = d.c + 1
    local k = deStr(d)
    d:toNext(); d:assertf(d.line and d.c <= #d.line,
      '.key must be followed by value')
    return k, d:getFn(d.line:sub(d.c,d.c))(d)
  end,
  ['{'] = deTableBracketed,
  ['@'] = function(d)
    d.c = d.c + 1; local k = deStr(d)
    d:toNext(); d:assertf(d.line and d.c <= #d.line,
      '@attr must be followed by value')
    d.enableAttrs = false
    local v = d:getFn(d.line:sub(d.c,d.c))(d)
    d.enableAttrs = nil
    local a = M.ATTR_ASSERTS[k]; if a then a(v) end
    d.attrs[k] = v
  end,
}

for b=byte'0',byte'9' do DE_CH[char(b)] = deInt end

M.De.nextLine = function(d)
  d.l, d.c = d.l + 1, 1; d.line = d.dat[d.l]
end
M.De.skipWs = function(d)
  while true do
    if not d.line then break end
    while #d.line == 0 do d:nextLine() end
    if d.c > #d.line and d.l < #d.dat then -- if EOL check for '+' on next line
      local nxt = d.dat[d.l + 1]
      local c1,c2 = nxt:find'%s*%+'
      if c2 then
        d:nextLine(); d.c = c2 + 1
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
  ::loop::
  d:toNext(); while d.line and d.c > #d.line do d:nextLine() end
  if not d.line then return end
  d:toNext()
  local ch = d.line and d.line:sub(d.c, d.c)
  if ch == '#' then d.header = deHeader(d); goto loop end
  if ch == '@' then DE_CH['@'](d);          goto loop end
  if ch == '!' then deDefine(d);            goto loop end
  local t = deTableUnbracketed(d, d.header)
  return (next(t) ~= nil) and t or nil
end

return M
