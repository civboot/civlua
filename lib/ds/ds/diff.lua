local G = G or _G

--- Patience diff implemented in Lua. Special thanks to:
--- https://blog.jcoglan.com/2017/09/19/the-patience-diff-algorithm/
---
--- The basic algorithm on before/after line lists: [+
--- * skip unchanged lines on both top and bottom
--- * find unique lines in both sets and "align" them with
---   using "longest increasing sequence"
--- * repeat for each "window"
--- ]
local M = G.mod and mod'ds.diff' or setmetatable({}, {})

local mty = require'metaty'
local ds  = require'ds'
local vcds = require'vcds'
local push = table.insert

M.ADD = '+'
M.REM = '-'
local ADD, REM = M.ADD, M.REM

--- Single Line Diff
--- This type is good for displaying differences to a user.
M.Diff = mty'Diff' {
  "b (base)   orig file.  '+'=added",
  "c (change) new file.   '-'=removed",
  "text[string]",
}
local Diff = M.Diff

getmetatable(M.Diff).__call = function(T, b, c, text)
  return mty.construct(T, {b=b, c=c, text=text})
end
M.Diff.__tostring = function(d)
  return string.format("%4s %4s|%s", d.b, d.c, d.text)
end
M.Diff.isKeep = function(d)
  return (d.b ~= ADD) and (d.c ~= REM)
end

--- indexed diff
M.DiffI = mty'DiffI' {
  'sym[string]: one of: [$" ", "+", "-"]',
  'b  [number]: base (original) line num',
  'c  [number]: change (new) line num',
}
local DiffI = M.DiffI

getmetatable(DiffI).__call = function(T, sym, b, c)
  return mty.construct(T, {sym=sym, b=b, c=c})
end
DiffI.__tostring = function(di) return string.format('DI(%s|%s)', di.b, di.c) end

--- [$c] is a table of [$lineStr -> unique].
--- The first time [$lineStr] is found, unique is set to the line number [$l].
--- Further times, unique is set to false (and remains false)
local function countLine(c, l, line)
  local r = c[line]
  if     r == nil   then c[line] = l; push(c, line)
  elseif r ~= false then c[line] = false end
end

--- two sync'd lists of base and change (i.e. matches, LIS, etc)
local _BC = mty'_BC'{'b [ints]', 'c [ints]'}

local uniqueMatches = function(bLines, cLines, b, b2, c, c2)
  local bcount, ccount = {}, {}
  for i=b,b2 do countLine(bcount, i, bLines[i]) end
  for i=c,c2 do countLine(ccount, i, cLines[i]) end
  local m = _BC{b={}, c={}}
  for _, line in ipairs((#bcount <= #ccount) and bcount or ccount) do
    local b, c = bcount[line], ccount[line]
    if bcount[line] and ccount[line] then
      push(m.b, b); push(m.c, c);
    end
  end
  return m
end

--- Find the stack to the left of where we should place
--- using binary search.
local findLeftStack = function(stacks, mc, c)
  local low, high, mid = 0, #stacks + 1
  while low + 1 < high do
    mid = (low + high) // 2
    if mc[stacks[mid]] < c then low  = mid
    else                        high = mid end
  end
  return low
end

--- Get the longest increasing sequence (in reverse order)
local patienceLIS = function(matches)
  local stacks = {}
  local mb, mc, prev, c, i = matches.b, matches.c, {}
  for mi, b in ipairs(matches.b) do
    i = findLeftStack(stacks, mc, mc[mi])
    if i > 0 then prev[mi] = stacks[i] end
    stacks[i+1] = mi
  end
  local mi = stacks[#stacks]; if not mi then return end
  local lis = {}
  while prev[mi] do push(lis, {mb[mi], mc[mi]}); mi = prev[mi] end
  push(lis, {mb[mi], mc[mi]})
  return lis
end

-- --- Used in LIS.
-- --- Find the stack to the left of where we should place [$b=match[2]]
-- local findLeftStack = function(stacks, c)
--   local low, high, mid = 0, #stacks + 1
--   while low + 1 < high do
--     mid = (low + high) // 2
--     if stacks[mid][2] < c then low  = mid
--     else                       high = mid end
--   end
--   return low
-- end
-- 
-- --- Get the longest increasing sequence (in reverse order)
-- local patienceLIS = function(matches)
--   local stacks = {}
--   for i, m in ipairs(matches) do
--     i = findLeftStack(stacks, m[2])
--     if i > 0 then m.prev = stacks[i] end
--     stacks[i+1] = m
--   end
--   local m = stacks[#stacks]; if not m then return end
--   local lis = {}
--   while m.prev do push(lis, {m[1], m[2]}); m = m.prev end
--   push(lis, {m[1], m[2]})
--   return lis
-- end

----------------------------
-- Compute the diff

local skipEqLinesTop = function(linesB, linesC, b, b2, c, c2) --> bi, ci
  while b <= b2 and c <= c2 do
    if linesB[b] ~= linesC[c] then return b, c end
    b, c = b + 1, c + 1
  end
  return b, c
end

local skipEqLinesBot = function(linesB, linesC, b, b2, c, c2) --> bi, ci
  while b <= b2 and c <= c2 do
    if linesB[b2] ~= linesC[c2] then return b2, c2 end
    b2, c2 = b2 - 1, c2 - 1
  end
  return b2, c2
end

local function addIs(out, sym, b1, c1, c2)
  for c=c1, c2 do push(out, DiffI(sym, b1, c)); b1 = b1 + 1 end
end

local diffI
--- calculate diff indexes and push to t
diffI = function(t, linesB, linesC, b, b2, c, c2) --> nil
  local bSt, b2St = b, b2
  local cSt, c2St = c, c2 -- for unchanged top bot lines
  b,  c  = skipEqLinesTop(linesB, linesC, b, b2, c, c2)
  b2, c2 = skipEqLinesBot(linesB, linesC, b, b2, c, c2)
  assert((c - cSt) == (b - bSt))

  addIs(t, ' ', bSt, cSt, c-1) -- unchanged lines (top)
  local matches = uniqueMatches(linesB, linesC, b, b2, c, c2)
  local lis = patienceLIS(matches)
  if not lis or #lis == 0 then
    for i=c,c2 do push(t, DiffI(ADD, nil, i)) end
    for i=b,b2 do push(t, DiffI(REM, i, nil)) end
    return
  end

  for i=#lis,0,-1 do
    local m = lis[i]; local bNext, cNext
    if m then bNext, cNext = m[1]-1, m[2]-1
    else      bNext, cNext = b2, c2 end
    diffI(t, linesB, linesC, b, bNext, c, cNext)
    if not m then break end
    push(t, DiffI(' ', m[1], m[2]))
    b, c = m[1] + 1, m[2] + 1
  end
  addIs(t, ' ', b2+1, c2+1, c2St) -- unchanged lines (bot)
end

M.diff = function(linesB, linesC) --> Diff
  local idx = {}
  diffI(idx, linesB, linesC, 1, #linesB, 1, #linesC)
  local diff = {}; for _, ki in ipairs(idx) do
    if     not ki.b then push(diff, Diff(ADD,  ki.c, linesC[ki.c]))
    elseif not ki.c then push(diff, Diff(ki.b, REM,  linesB[ki.b]))
    else                 push(diff, Diff(ki.b, ki.c, linesC[ki.c])) end
  end
  return diff
end
local diff = M.diff

M._forTest = {
  uniqueMatches = uniqueMatches,
  findLeftStack = findLeftStack,   patienceLIS   = patienceLIS,
  skipEqLinesTop = skipEqLinesTop, skipEqLinesBot = skipEqLinesBot,
  _BC = _BC,
}

getmetatable(M).__call = function(_, ...) return diff(...) end
return M
