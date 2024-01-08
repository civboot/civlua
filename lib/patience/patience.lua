-- Patience diff implemented in Lua. Special thanks to:
-- https://blog.jcoglan.com/2017/09/19/the-patience-diff-algorithm/

local add = table.insert
local M = {}

local function ensureCount(t, line)
  local v = t[line]; if v then return v end
  v = {0, 0, false, false} -- aCount, bCount, aLineI, bLineI
  t[line] = v; add(t, v)
  return v
end

function M.uniqueMatches(aLines, bLines, a, a2, b, b2)
  local counts, matches, line, c = {}, {}
  for i=a,a2 do
    line = aLines[i]; c = ensureCount(counts, line)
    c[1] = c[1] + 1; c[3] = i
  end
  for i=b,b2 do
    line = bLines[i]; c = ensureCount(counts, line)
    c[2] = c[2] + 1; c[4] = i
  end
  for _, c in ipairs(counts) do
    if c[1] == 1 and c[2] == 1 then add(matches, {c[3], c[4]}) end
  end
  return matches
end

-- find the stack to the left of where we should place b=match[2]
function M.findLeftStack(stacks, b)
  local low, high, mid = 0, #stacks + 1
  while low + 1 < high do
    mid = (low + high) // 2
    if stacks[mid][2] < b then low  = mid
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
  while m.prev do add(lis, {m[1], m[2]}); m = m.prev end
  add(lis, {m[1], m[2]})
  return lis
end

----------------------------
-- Compute the diff

M.DiffI = setmetatable(
  { __tostring=function(di) return string.format('DI(%s|%s)', di.a, di.b) end },
  { __call = function(ty_, sym, a, b)
      return setmetatable({sym=sym, a=a, b=b}, ty_)
    end,
  })

M.skipEqLinesTop = function(linesA, linesB, a, a2, b, b2)
  while a <= a2 and b <= b2 do
    if linesA[a] ~= linesB[b] then return a, b end
    a = a+1; b = b+1
  end
  return a, b
end

M.skipEqLinesBot = function(linesA, linesB, a, a2, b, b2)
  while a <= a2 and b <= b2 do
    if linesA[a2] ~= linesB[b2] then return a2, b2 end
    a2 = a2-1; b2 = b2-1
  end
  return a2, b2
end

local function addIs(out, sym, a1, b1, b2)
  for b=b1, b2 do add(out, M.DiffI(sym, a1, b)); a1 = a1 + 1 end
end

M.diffI = function(diff, linesA, linesB, a, a2, b, b2)
  local aSt, a2St = a, a2
  local bSt, b2St = b, b2 -- for unchanged top bot lines
  a,  b  = M.skipEqLinesTop(linesA, linesB, a, a2, b, b2)
  a2, b2 = M.skipEqLinesBot(linesA, linesB, a, a2, b, b2)
  assert((b - bSt) == (a - aSt))

  addIs(diff, ' ', aSt, bSt, b-1) -- unchanged lines (top)
  local matches = M.uniqueMatches(linesA, linesB, a, a2, b, b2)
  local lis = M.patienceLIS(matches)
  if not lis or #lis == 0 then
    for i=b,b2 do add(diff, M.DiffI('+', nil, i)) end
    for i=a,a2 do add(diff, M.DiffI('-', i, nil)) end
    return
  end

  for i=#lis,0,-1 do
    m = lis[i]; local aNext, bNext
    if m then aNext, bNext = m[1]-1, m[2]-1
    else      aNext, bNext = a2, b2 end
    M.diffI(diff, linesA, linesB, a, aNext, b, bNext)
    if not m then break end
    add(diff, M.DiffI(' ', m[1], m[2]))
    a, b = m[1] + 1, m[2] + 1
  end
  addIs(diff, ' ', a2+1, b2+1, b2St) -- unchanged lines (bot)
end

----------------------------
-- Format the Diff
local function nw(n) -- numwidth
  if n == nil then return '        ' end
  n = tostring(n); return n..string.rep(' ', 8-#n)
end

M.Diff = setmetatable(
  {__tostring=function(di)
    return
      ((not di.a and '+') or (not di.b and '-') or ' ')
      ..nw(di.a)..nw(di.b)..'| '..di.text
  end},
  { __call = function(ty_, text, a, b)
      return setmetatable({text=text, a=a, b=b}, ty_)
    end,
  })

M.diff = function(linesA, linesB)
  local idx = {}
  M.diffI(idx, linesA, linesB, 1, #linesA, 1, #linesB)
  local diff = {}
  for _, ki in ipairs(idx) do
    if     not ki.a then add(diff, M.Diff(linesB[ki.b], ki.a, ki.b))
    elseif not ki.b then add(diff, M.Diff(linesA[ki.a], ki.a, ki.b))
    else                 add(diff, M.Diff(linesB[ki.b], ki.a, ki.b)) end
  end
  return diff
end

return M
