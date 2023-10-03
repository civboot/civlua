
-- Patience diff
--
-- Thanks to https://blog.jcoglan.com/2017/09/19/the-patience-diff-algorithm/

local add = table.insert
local last = function(t) return t[#t] end

local M = {}

-- Count{i, count, nxt} used in the patience diff.
--   `i`: line index
--   count: how many there are
--   nxt: next stack (patience stacks)
M.Count = setmetatable(
  { __tostring=function(c) return string.format('C@%s', c.i) end },
  {
    __call = function(ty_, i) return setmetatable({i=i or 1, count=1}, ty_) end,
  })

M.DiffI = setmetatable(
  { __tostring=function(di) return string.format('DI(%s|%s)', di.a, di.b) end },
  { __call = function(ty_, sym, b, a)
      return setmetatable({sym=sym, a=a, b=b}, ty_)
    end,
  })

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

-- Return MapA[line, CountA] and MapB[line, CountB].
--
-- countB contains only items which are unique (count==1) from countA
-- and which were added in increasing order from A.
--
-- This is so that we only output unique AND increasing matching indexes.
-- For example
--     A    B
--    --------
--     1    3    /- therefore 3 can't match
--     2 \- 1  1 matches with 1
--     3    4
--
-- Diff result:
--     A    B
--    --------
--   +      3
--     1    1
--   - 2
--   - 3
--   +      4
--
-- Note: Only count == 1 from countB should be used in the patience stacks.
M.linesUniqueCountMaps = function(linesA, linesB, a, a2, b, b2)
  local countA = {}
  for a=a,a2 do
    local line = linesA[a]
    local c = countA[line]
    if not c then
      c = M.Count(); countA[line] = c
    end
    c.i = a; c.count = c.count + 1
  end
  local countB = {}
  a = 0
  for b=b,b2 do
    local line = linesB[b]
    local cA = countA[line]
    if cA and cA.count == 1 and a < cA.i then
      local cB = countB[line]
      if not cB then
        cB = M.Count()
        countB[line] = cB
      end
      cB.i = b; eB.count = eB.count + 1
      a = cA.i
    end
  end
  return countA, countB
end

-- Return the patience stacks from countMap.
--
-- Patience stacks are a set of stacks sorted using line indexes of unique lines.
--
-- The algorithm is akin to playing a simplistic game of "patience" (aka
-- solitare) where the top of each stack has a smaller value than the item below
-- it or it's added to the next stack.
--
-- This allows us to get the Longest Increasing Subsequence with patienceLIS.
M.patienceStacks = function(countMap)
  local stacks = {}
  for _, c in pairs(countMap) do
    for si, s in ipairs(stacks) do
      local top = s[#s]
      if c.i < top.i then
        if si > 1 then
          -- set nxt to top of prev stack
          -- (unless this is si==1, the first stack)
          c.nxt = last(stacks[si-1])
        end
        add(s, c)
        goto contOuter
      end
    end
    if 0 == #stacks then add(stacks, {c})
    else
      -- no stack found, create one and set nxt
      -- to prev stack top
      c.nxt = last(stacks[#stacks])
      add(stacks, {c})
    end
    ::contOuter::
  end
  return stacks
end

-- Return the Longest Increasing Subsequence of count.i
-- from the patienceStacks.
--
-- countMap should come from linesUniqueCountMaps.
M.patienceLIS = function(stacks)
  local lis = {}; for _, s in ipairs(stacks) do add(lis, last(s).i) end
  return lis
end

-- Walk lines at the top (index=1), skipping equal lines.
--
-- Items i<a and i<b are equal to eachother (or vice-versa if inc==-1).
M.skipEqLinesTop = function(linesA, linesB, a, a2, b, b2)
  while a <= a2 and b <= b2 do
    if linesA[a] ~= linesB[b] then return a, b end
    a = a+1; b = b+1
  end
  return a, b
end

-- Walk lines at the bot (index=-1) skipping equal lines.
--
-- Items i>a2 and i>b2 are equal to eachother
M.skipEqLinesBot = function(linesA, linesB, a, a2, b, b2)
  while a <= a2 and b <= b2 do
    if linesA[a2-1] ~= linesB[b2-1] then return a2, b2 end
    a2 = a2-1; b2 = b2-1
  end
  return a2, b2
end

local function addIs(out, sym, b1, b2, a1)
  for b=b1, b2 do
    add(out, M.DiffI(sym, b, a1))
    a1 = a1 + 1
  end
end

-- Get the patience dif indexes (a/b indexes inclusive).
M.diffI = function(out, linesA, linesB, a, a2, b, b2)
  local aSt, a2St = a, a2
  local bSt, b2St = b, b2 -- cache absolute (starting) min/max of b
  a,  b  = M.skipEqLinesTop(linesA, linesB, a, a2, b, b2)
  a2, b2 = M.skipEqLinesBot(linesA, linesB, a, a2, b, b2)

  assert((b - bSt) == (a - aSt))
  -- B unchanged lines (top)
  -- for i=bSt, b-1 do add(out, {' ', i}) end
  addIs(out, ' ', bSt, b-1, aSt)

  -- find changed lines
  local countMapA, countMapB = M.linesUniqueCountMaps(linesA, linesB, a, a2, b, b2)
  local stacksB = M.patienceStacks(countMapB)
  local lisB = M.patienceLIS(stacksB)

  -- divide and conquere: split by changed lines and recurse
  -- into a sub-patience diff.
  -- i is the lower bound and b the moving upper bound.
  local i = 1
  local a2Mid = a2 -- cache absolute (pre divide) min/max of a
  while i < #lisB do
    -- bsi=bSplitIndex, we know we have equal lines here
    bsi = lisB[i]
    line = linesB[bsi]; a = countMapA[line].i
    -- bSplitIndex2 is at either next split index or the end of b
    bsi2 = lisB[i+1] or b2
    line2 = linesB[bsi2]
    if line2 then a2 = countMapA[line2].i
    else          a2 = a2Mid end
    assert(a <= a2); assert(b <= b2);
    add(out, M.DiffI(' ', line, a))
    patienceDiff(out, linesA, linesB, a+1, a2-1, i+1, b-1)
    b = bsi + 1
    i = i
  end
  if #lisB == 0 then
    for i=b,b2-1 do add(out, M.DiffI('+', i, nil)) end
    for i=a,a2-1 do add(out, M.DiffI('-', nil, i)) end
  end
  assert(b <= b2)
  assert((b2 - b2St) == (a2 - a2St))

  -- B unchanged lines (top)
  -- for i=b2,b2St do add(out, {' ', i}) end
  addIs(out, ' ', b2, b2St, a2)

  return out
end

M.diff = function(linesA, linesB)
  local indexes = {}
  M.diffI(indexes, linesA, linesB, 1, #linesA, 1, #linesB)
  local diff = {}
  for _, ki in ipairs(indexes) do
    if     not ki.a then add(diff, M.Diff(linesB[ki.b], ki.a, ki.b))
    elseif not ki.b then add(diff, M.Diff(linesA[ki.a], ki.a, ki.b))
    else                 add(diff, M.Diff(linesB[ki.b], ki.a, ki.b)) end
  end
  return diff
end

return M
