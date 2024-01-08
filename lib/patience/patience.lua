-- Patience diff implemented in Lua. Special thanks to:
-- https://blog.jcoglan.com/2017/09/19/the-patience-diff-algorithm/

local mty = require'metaty'
local ds  = require'ds'
local Keep, Chng; local patch = mty.lrequire'patch'
local push = table.insert
local M = {}

local function ensureCount(t, line)
  local v = t[line]; if v then return v end
  v = {0, 0, false, false} -- aCount, bCount, aLineI, bLineI
  t[line] = v; push(t, v)
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
    if c[1] == 1 and c[2] == 1 then push(matches, {c[3], c[4]}) end
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
  while m.prev do push(lis, {m[1], m[2]}); m = m.prev end
  push(lis, {m[1], m[2]})
  return lis
end

----------------------------
-- Compute the diff

M.DiffI = mty.record'patience.DiffI'
  :field('sym', 'string')
  :fieldMaybe('a', 'number')
  :fieldMaybe('b', 'number')
  :new(function(ty_, sym, a, b) return mty.new(ty_, {sym=sym, a=a, b=b}) end)
M.DiffI.__tostring = function(di) return string.format('DI(%s|%s)', di.a, di.b) end


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
  for b=b1, b2 do push(out, M.DiffI(sym, a1, b)); a1 = a1 + 1 end
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
    for i=b,b2 do push(diff, M.DiffI('+', nil, i)) end
    for i=a,a2 do push(diff, M.DiffI('-', i, nil)) end
    return
  end

  for i=#lis,0,-1 do
    m = lis[i]; local aNext, bNext
    if m then aNext, bNext = m[1]-1, m[2]-1
    else      aNext, bNext = a2, b2 end
    M.diffI(diff, linesA, linesB, a, aNext, b, bNext)
    if not m then break end
    push(diff, M.DiffI(' ', m[1], m[2]))
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

M.Diff = mty.record'patience.Diff'
  :field('text', 'string')
  :fieldMaybe('a', 'number')
  :fieldMaybe('b', 'number')
  :new(function(ty_, text, a, b)
    return mty.new(ty_, {text=text, a=a, b=b})
  end)

M.Diff.__tostring = function(di)
 return
   ((not di.a and '+') or (not di.b and '-') or ' ')
   ..nw(di.a)..nw(di.b)..'| '..di.text
end

M.diff = function(linesA, linesB)
  local idx = {}
  M.diffI(idx, linesA, linesB, 1, #linesA, 1, #linesB)
  local diff = {}
  for _, ki in ipairs(idx) do
    if     not ki.a then push(diff, M.Diff(linesB[ki.b], ki.a, ki.b))
    elseif not ki.b then push(diff, M.Diff(linesA[ki.a], ki.a, ki.b))
    else                 push(diff, M.Diff(linesB[ki.b], ki.a, ki.b)) end
  end
  return diff
end

local function pushAdd(ch, text)
  mty.pntf('??   pushAdd %q', text)
  if not ch.add then ch.add = {} end
  push(ch.add, text)
end

M.patches = function(diff)
  local patches, p = {}, nil
  for _, d in ipairs(diff) do
    if d.a and d.b then -- keep
      if not p or mty.ty(p) ~= Keep then push(patches, p); p = Keep{num=0} end
      p.num = p.num + 1
    else
      if not p or mty.ty(p) ~= Chng then push(patches, p); p = Chng{rem=0} end
      if not d.a                    then pushAdd(p, d.text)
      else assert(not d.b);              p.rem = p.rem + 1 end
    end
  end
  if p then push(patches, p) end
  return patches
end

return M
