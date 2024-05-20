-- lines module, when called splits a string into lines.
--
-- lines(text) -> table of lines
--
-- Also has functions for working with a table of lines.
--
--   lines.sub(myLines, l, c, l2, c2)
local M = mod and mod'ds.lines' or {}

local mty = require'metaty'
local ds  = require'ds'
local push, pop = table.insert, table.remove
local max, min, bound = math.max, math.min, ds.bound

M.CMAX = 999

setmetatable(M, {
  __call=function(_, text, index)
    local t = {}
    for _, line in mty.rawsplit, text, {'\n', index or 1} do
      push(t, line)
    end; return t
  end,
})

-- insert (typically integer) index into list-like type
-- Uses __insertline else default table implementation
M.insert = function(t, s, l, c)
  local meth = mty.getmethod(t, '__insertline')
  if meth then return meth(t, s, l, c) end
  local cur = pop(t, assert(l))
  ds.extend(t, ds.strInsert(cur, c or 1, s))
end

-- Address lines span via either (l,l2) or (l,c, l2,c2)
local function span(l, c, l2, c2)
  if not (l2 or c2) then return l, nil, c, nil end --(l,   l2)
  if      l2 and c2 then return l, c, l2, c2   end --(l,c, l2,c2)
  error'span must be 2 or 4 indexes: (l, l2) or (l, c, l2, c2)'
end
M.span = span

local function _lsub(sub, slen, t, ...)
  local l, c, l2, c2 = span(...)
  local len = #t
  local lb, lb2 = ds.bound(l, 1, len), ds.bound(l2, 1, len+1)
  if lb  > l  then c = 1 end
  if lb2 < l2 then c2 = nil end -- EoL
  l, l2 = lb, lb2
  local s = {} -- s is sub
  for i=l,l2 do push(s, t[i]) end
  if    nil == c then -- skip, only lines
  elseif #s == 0 then s = '' -- empty
  elseif l == l2 then
    assert(1 == #s); local line = s[1]
     s = sub(line, c, c2)
    if c2 > slen(line) and l2 < len then s = s..'\n' end
  else
    local last = s[#s]
    s[1] = sub(s[1], c); s[#s] = sub(last, 1, c2)
    if c2 > #last and l2 < len then push(s, '') end
    s = table.concat(s, '\n')
  end
  return s
end

M.sub  = function(...) return _lsub(string.sub, string.len, ...) end
M.usub = function(...) return _lsub(ds.usub,     utf8.len,   ...) end

M.diff = function(linesL, linesR)
  local i = 1
  while i <= #linesL and i <= #linesR do
    local lL, lR = linesL[i], linesR[i]
    if lL ~= lR then
      return i, assert(ds.diffCol(lL, lR))
    end
    i = i + 1
  end
  if #linesL < #linesR then return #linesL + 1, 1 end
  if #linesR < #linesL then return #linesR + 1, 1 end
  return nil
end

-- create a table of lineText -> {lineNums}
M.map = function(lines)
  local map = {}; for l, line in ipairs(lines) do
    push(ds.getOrSet(map, line, ds.emptyTable), l)
  end
  return map
end

-- bound the line/col for the gap
M.bound = function(t, l, c, len, line)
  len = len or #t
  l = bound(l, 1, len)
  if not c then return l end
  return l, bound(c, 1, #(line or t[l]) + 1)
end

-- Get the l, c with the +/- offset applied
M.offset=function(t, off, l, c)
  local len, m, llen, line = #t
  -- 0 based index for column
  l = bound(l, 1, len); c = bound(c - 1, 0, #t[l])
  while off > 0 do
    line = t[l]
    if nil == line then return len, #t[len] + 1 end
    llen = #line + 1 -- +1 is for the newline
    c = bound(c, 0, llen); m = llen - c
    if m > off then c = c + off; off = 0;
    else l, c, off = l + 1, 0, off - m
    end
    if l > len then return len, #t[len] + 1 end
  end
  while off < 0 do
    line = t[l]
    if nil == line then return 1, 1 end
    llen = #line
    c = bound(c, 0, llen); m = -c - 1
    if m < off then c = c + off; off = 0
    else l, c, off = l - 1, M.CMAX, off - m
    end
    if l <= 0 then return 1, 1 end
  end
  l = bound(l, 1, len)
  return l, bound(c, 0, #t[l]) + 1
end

M.offsetOf=function(t, l, c, l2, c2)
  local off, len, llen = 0, #t
  l, c = M.bound(t, l, c, len);  l2, c2 = M.bound(t, l2, c2, len)
  c, c2 = c - 1, c2 - 1 -- column math is 0-indexed
  while l < l2 do
    llen = #t[l] + 1
    c = bound(c, 0, llen)
    off = off + (llen - c)
    l, c = l + 1, 0
  end
  while l > l2 do
    llen = #t[l] + ((l==len and 0) or 1)
    c = bound(c, 0, llen)
    off = off - c
    l, c = l - 1, M.CMAX
  end
  llen = #t[l] + ((l==len and 0) or 1)
  c, c2 = bound(c, 0, llen), bound(c2, 0, llen)
  off = off + (c2 - c)
  return off
end

-- find the pattern starting at l/c
-- Note: matches are only within a single line.
M.find = function(t, pat, l, c) --> (l, c)
  l, c = l or 1, c or 1
  while true do
    local s = t[l]
    if not s then return nil end
    c = s:find(pat, c); if c then return l, c end
    l, c = l + 1, 1
  end
end

local findBack = function(s, pat, end_)
  local s, fs, fe = s:sub(1, end_), nil, 0
  assert(#s < 256)
  while true do
    local _fs, _fe = s:find(pat, fe + 1)
    if not _fs then break end
    fs, fe = _fs, _fe
  end
  if fe == 0 then fe = nil end
  return fs, fe
end

-- find the pattern (backwards) starting at l/c
M.findBack = function(t, pat, l, c)
  while true do
    local s = t[l]
    if not s then return nil end
    c = findBack(s, pat, c)
    if c then return l, c end
    l, c = l - 1, nil
  end
end

return M
