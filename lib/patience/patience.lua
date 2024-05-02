-- Patience diff implemented in Lua. Special thanks to:
-- https://blog.jcoglan.com/2017/09/19/the-patience-diff-algorithm/

local pkg = require'pkglib'
local mty = pkg'metaty'
local ds  = pkg'ds'
local vcds = pkg'vcds'
local push = table.insert
local M = {}

local DiffI = mty.record2'patience.DiffI' {
  'sym[string]: {" " + -}',
  'b  [number]: base (original) line num',
  'c  [number]: change (new) line num',
}
getmetatable(DiffI).__call = function(T, sym, b, c)
  return mty.construct(T, {sym=sym, b=b, c=c})
end
DiffI.__tostring = function(di) return string.format('DI(%s|%s)', di.b, di.c) end

local function ensureCount(t, line)
  local v = t[line]; if v then return v end
  v = {0, 0, false, false} -- aCount, bCount, aLineI, bLineI
  t[line] = v; push(t, v)
  return v
end

function M.uniqueMatches(aLines, bLines, b, b2, c, c2)
  local counts, matches, line, ct = {}, {}
  for i=b,b2 do
    line = aLines[i]; ct = ensureCount(counts, line)
    ct[1] = ct[1] + 1; ct[3] = i
  end
  for i=c,c2 do
    line = bLines[i]; ct = ensureCount(counts, line)
    ct[2] = ct[2] + 1; ct[4] = i
  end
  for _, ct in ipairs(counts) do
    if ct[1] == 1 and ct[2] == 1 then push(matches, {ct[3], ct[4]}) end
  end
  return matches
end

-- find the stack to the left of where we should place b=match[2]
function M.findLeftStack(stacks, c)
  local low, high, mid = 0, #stacks + 1
  while low + 1 < high do
    mid = (low + high) // 2
    if stacks[mid][2] < c then low  = mid
    else                       high = mid end
  end
  return low
end

-- Get the longest increasing sequence (in reverse order)
function M.patienceLIS(matches)
  local stacks = {}
  for i, m in ipairs(matches) do
    i = M.findLeftStack(stacks, m[2])
    if i > 0 then m.prev = stacks[i] end
    stacks[i+1] = m
  end
  local m = stacks[#stacks]; if not m then return end
  local lis = {}
  while m.prev do push(lis, {m[1], m[2]}); m = m.prev end
  push(lis, {m[1], m[2]})
  return lis
end

----------------------------
-- Compute the diff

M.skipEqLinesTop = function(linesB, linesC, b, b2, c, c2)
  while b <= b2 and c <= c2 do
    if linesB[b] ~= linesC[c] then return b, c end
    b = b+1; c = c+1
  end
  return b, c
end

M.skipEqLinesBot = function(linesB, linesC, b, b2, c, c2)
  while b <= b2 and c <= c2 do
    if linesB[b2] ~= linesC[c2] then return b2, c2 end
    b2 = b2-1; c2 = c2-1
  end
  return b2, c2
end

local function addIs(out, sym, b1, c1, c2)
  for c=c1, c2 do push(out, DiffI(sym, b1, c)); b1 = b1 + 1 end
end

M.diffI = function(diff, linesB, linesC, b, b2, c, c2)
  local bSt, b2St = b, b2
  local cSt, c2St = c, c2 -- for unchanged top bot lines
  b,  c  = M.skipEqLinesTop(linesB, linesC, b, b2, c, c2)
  b2, c2 = M.skipEqLinesBot(linesB, linesC, b, b2, c, c2)
  assert((c - cSt) == (b - bSt))

  addIs(diff, ' ', bSt, cSt, c-1) -- unchanged lines (top)
  local matches = M.uniqueMatches(linesB, linesC, b, b2, c, c2)
  local lis = M.patienceLIS(matches)
  if not lis or #lis == 0 then
    for i=c,c2 do push(diff, DiffI('+', nil, i)) end
    for i=b,b2 do push(diff, DiffI('-', i, nil)) end
    return
  end

  for i=#lis,0,-1 do
    m = lis[i]; local bNext, cNext
    if m then bNext, cNext = m[1]-1, m[2]-1
    else      bNext, cNext = b2, c2 end
    M.diffI(diff, linesB, linesC, b, bNext, c, cNext)
    if not m then break end
    push(diff, DiffI(' ', m[1], m[2]))
    b, c = m[1] + 1, m[2] + 1
  end
  addIs(diff, ' ', b2+1, c2+1, c2St) -- unchanged lines (bot)
end

----------------------------
-- Convert to vcds.Diff
M.diff = function(linesB, linesC)
  local idx, Diff, ADD, REM = {}, vcds.Diff, vcds.ADD, vcds.REM
  M.diffI(idx, linesB, linesC, 1, #linesB, 1, #linesC)
  local diff = {}; for _, ki in ipairs(idx) do
    if     not ki.b then push(diff, Diff(ADD,  ki.c, linesC[ki.c]))
    elseif not ki.c then push(diff, Diff(ki.b, REM,  linesB[ki.b]))
    else                 push(diff, Diff(ki.b, ki.c, linesC[ki.c])) end
  end
  return diff
end

return M
