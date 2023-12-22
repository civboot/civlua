
local mty = require'metaty'
local ds  = require'ds'; local lines = ds.lines
local push, sfmt = table.insert, string.format


local M = mty.docTy({}, [[
RNV: return nested values.

See README for in-depth documentation.
]])

local CH_0 = string.byte'0'
local escPat = '[\n\t\\]'
local INF, NEG_INF = 1/0, -1/0
local NAN_STR, INF_STR, NEG_INF = 'nan', 'inf', '-inf'

M.Ser = mty.record'rnv.Ser'
  :field'dat'    :fdoc'output lines'
  :field'line'   :fdoc'current line table'
  :field'headers':fdoc'map of header keys at levels'
  :field'attrs'
  :field('nest', 'number')
  :field'r':fdoc'current row (for debug)'


-- valid escape.
-- a '\' will only be serialized as '\\' if it is followed
-- by one of these. Conversly, when deserializing a '\'
-- it is itself unless followed by one of these.
local escValid = ds.Set{
  'n', 't', '\n', '\\',
}

-- escape a string used as a key
M.escapeKey = function(str)
  return str
end

-- escape a string
M.escape = function(str)
  return str
end

local function _description(ser, d)
  local q, q2 = d:find'"+'; if q then q = q2 - q + 1 end
  if q or d:find'\n' then
    q = string.rep('"', q + 1)
    push(ser.dat, q)
    for _, line in mty.split(d, '\n') do push(ser.dat, line) end
    push(ser.dat, q)
  else push(ser.dat, '"'..d..'"') end
end

local function _header(out, h, hi)
  local hname = hi and ('headers index='..hi) or 'header'
  mty.assertf(type(depth) == 'number' , '%s: depth must be a number', hname)
  local line = {'#', utf8.char(CH_0 + depth), ' '}
  for i, k in ipairs(h) do
     mty.assertf(type(k) == 'string', '%s: index=%s is not a string', hname, i)
     push(line, '"'); push(line, M.escapeKey(k))
  end
  push(out, table.concat(line, '\t'))
end

local function _headers(out, headers)
  local depths = {}
  for hi, h in ipairs(headers) do
    mty.assertf(h.depth, 'headers index %s: must specify depth', hi)
    mty.assertf(not depths[h.depth], 'multiple header depth=%s', h.depth)
    depths[h.depth] = true
    _header(out, h, hi)
  end
end

local INT_FMT   = {[10]='d', [16]='x'}

local SER = {
  ['nil'] = function(ser) ser:error'nil values not permitted' end,
  boolean = function(ser, b) return b and 't' or 'f' end,
  number  = function(ser, n)
    if n == math.floor(n) then -- integer
      local nbase = ser.attrs.nbase or 10
      if nbase == 10     then push(ser.line, sfmt('%d', n))
      elseif nbase == 16 then push(ser.line, sfmt('%X', n))
      else error'invalid nbase' end
    else -- float
      ser:error'floats not yet supported'
      -- if n ~= n then push(ser.line, '^NaN')
      -- else push(ser.line, sfmt('^%a', n)) end
    end
  end,
  string = function(ser, s)
    local i, slen, line, out = 1, #s, ser.line, ser.dat
    push(line, '"')
    while i <= slen do
      local c1 = s:find(escPat, i)
      if not c1 then push(line, s:sub(i)); break end
      local ch = f:sub(c1,c1)
      if ch == '\n' then
        push(line, s:sub(i, c1-1))
        push(out, table.concat(line, ''))
        line = {"'"}
      elseif ch == '\t' then
        push(line, s:sub(i, c1-1))
        push(line, [[\t]])
        if ch == '\\' then
          push(line, s:sub(i, c1))
          if escValid[s:sub(i, c1+1)] then push(line, '\\') end
        end
      end
      i = c1 + 1
    end
    ser.line = line
  end,
  table = function(ser, t)
    error'not impl'
    -- 'none'  = function(ser) return 'n' end,
  end,
}

local function _row(ser, row)
  assert(#ser.line == 0)
  push(ser.line, string.char(CH_0 + ser.nest)); push(ser.line, ' ')
  local len = #row
  for i, v in ipairs(row) do
    mty.pnt('?? _row i='..i..' v:', v)
    local ty = type(v)
    local fn = mty.assertf(SER[ty], 'can not serialize type %s', ty)
    fn(ser, v)
    if i < len then push(ser.line, '\t') end
  end
  -- TODO: do keys
  if #ser.line then
    push(ser.dat, table.concat(ser.line))
    ser.line = {}
  end
end

M.serialize = function(args)
  local data = assert(args.data or args[1], 'must specify data as arg 1')
  local ser = M.Ser {
    dat     = args.out or args[2] or {},
    line    = {}, headers = {},
    attrs   = {},
    nest = 0, r = 0,
  }

  if args.comment  then push(ser.dat, '- '..args.comment) end
  if args.desc     then _description(ser, args.desc)  end
  if args.header   then _header(ser, args.header)     end
  if args.headers  then _headers(ser, args.headers)   end
  for r, row in ipairs(data) do
    mty.pnt('?? ser row', row)
    ser.r = r; _row(ser, row)
  end
  return ser.dat, ser
end

return M
