local mty = require'metaty'
local ds  = require'ds'; local lines = ds.lines
local concat, push, sfmt = table.concat, table.insert, string.format

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
M.SER_TY = {}

local escPat = '[\n\t\\]'
local INF, NEG_INF = 1/0, -1/0
local NAN_STR, INF_STR, NEG_INF = 'nan', 'inf', '-inf'

-- valid escapes (in a string)
-- a '\' will only be serialized as '\\' if it is followed
-- by one of these. Conversly, when deserializing a '\'
-- it is itself unless followed by one of these.
local escValid = ds.Set{
  'n', 't', '\n', '\\',
}

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
    elseif ibase == 16 then push(ser.line, sfmt('%X', n))
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
        if escValid[s:sub(i, c1+1)] then push(line, '\\') end
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

return M
