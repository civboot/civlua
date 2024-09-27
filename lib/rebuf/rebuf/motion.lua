local mty = require'metaty'
local ds = require'ds'
local min, max, sort2, bound, isWithin; ds.auto'ds'

local M = {}
local byte, char = string.byte, string.char

--- decrease distance (start -> end) by 1
M.decDistance = function(s, e) --> int
  if s == e then return e end
  return (s < e) and (e - 1) or (e + 1)
end

--- return whether l.c is <= l2.c2
M.lcLe = function(l, c, l2, c2) --> bool
  if l == l2 then return c <= c2 end
  return l < l2
end

--- return whether l.c is >= l2.c2
M.lcGe = function(l, c, l2, c2) --> bool
  if l == l2 then return c >= c2 end
  return l > l2
end

--- return the top-left of two points
M.topLeft = function(l, c, l2, c2) --> (l, c)
  if not c then
    assert(not c2); return sort2(l, l2)
  end
  if l == l2 then return l, min(c, c2) end
  if l <  l2 then return l, c end
  return l2, c2
end

-- return whether a cursor is within a range
M.lcWithin = function(l, c, l1, c1, l2, c2) --> bool
  if l1 > l2 then l1, c1, l2, c2 = l2, c2, l1, c1
  elseif l1 == l2 then
    c1, c2 = sort2(c1, c2)
    return l == l1 and isWithin(c, c1, c2)
  end
  if isWithin(l, l1, l2) then
    if l == l1 then return c >= c1 end -- bottom
    if l == l2 then return c <= c2 end -- top
    return true
  end
  return false
end

local WordKind = {}; M.WordKind = WordKind -- ws, sym, let
for c=0, 127 do
  local ch, kind = char(c), nil
  if 0 <= c and ch <= ' '        then kind = 'ws'
  elseif '1' <= ch and ch <= '9' then -- let, leave
  elseif 'a' <= ch and ch <= 'z' then -- let, leave
  elseif 'A' <= ch and ch <= 'Z' then -- let, leave
  elseif ch == '_'               then -- let, leave
  else kind = 'sym' end
  WordKind[ch] = kind
end
WordKind['('] = '()'; WordKind[')'] = '()'
WordKind['['] = '[]'; WordKind[']'] = '[]'
WordKind['{'] = '{}'; WordKind['}'] = '{}'
WordKind['"'] = '"'   WordKind["'"] = "'"

local function wordKind(ch) return WordKind[ch] or 'let' end
M.wordKind = wordKind --> string

--- Go forward to find the start of the next word
M.forword = function(s, begin) --> int
  begin = begin or 1
  local i, kStart = begin+1, wordKind(s:sub(begin,begin))
  for ch in string.gmatch(s:sub(begin+1), '.') do
    local k = wordKind(ch)
    if k ~= kStart then
      if kStart ~= 'ws' and k == 'ws' then
        kStart = 'ws' -- find first non-whitespace
      else return i end
    end
    i = i + 1
  end
end

--- Go backward to find the start of this (or previous) word
M.backword = function(s, end_) --> int
  s = s:sub(1, end_-1):reverse()
  local i, kStart = 2, wordKind(s:sub(1,1))
  for ch in string.gmatch(s:sub(2), '.') do
    local k = wordKind(ch)
    if k ~= kStart then
      if kStart == 'ws' then kStart = k
      else return #s - i + 2 end
    end
    i = i + 1
  end
end

--- find backwards
--- this searches for the pattern and returns the LAST one found.
--- This is HORRIBLY non-performant, only use for small amounts of data
M.findBack = function(s, pat, end_, plain) --> int
  local s, fs, fe = s:sub(1, end_), nil, 0
  assert(#s < 256)
  while true do
    local _fs, _fe = s:find(pat, fe + 1, plain)
    if not _fs then break end
    fs, fe = _fs, _fe
  end
  if fe == 0 then fe = nil end
  return fs, fe
end

return M
