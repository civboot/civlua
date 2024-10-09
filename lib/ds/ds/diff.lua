local G = G or _G

local M = G.mod and mod'ds.diff' or setmetatable({}, {})

local mty = require'metaty'
local ds  = require'ds'
local push = table.insert
local clear = ds.clear
local construct = mty.construct
local str, sfmt = tostring, string.format


--- Line-based diff.
--- The default algorithm uses patience diff. Special thanks to:
--- [<https://blog.jcoglan.com/2017/09/19/the-patience-diff-algorithm>]
---
--- The basic algorithm on before/after line lists: [+
--- * skip unchanged lines on both top and bottom
--- * find unique lines in both sets and "align" them with
---   using "longest increasing sequence"
--- * repeat for each aligned section
--- ]
---
--- Example: [$io.fmt(Diff(linesA, linesB))]
M.Diff = mty'Diff' {
  'b [lines]: base, aka original lines',
  'c [lines]: change, aka new lines',
  'di [int]: len of noc/rem/add',
  'noc [ints]: nochange range (in both)',
  'rem [ints]: removed from b',
  'add  [ints]: added from c',
}
local Diff = M.Diff

--- [$c] is a table of [$lineStr -> lineNum].
--- The first time [$lineStr] is found the line number [$l] is stored.
--- If found again, the stored line is set to false (and remains false)
---
--- The [$line] string is also pushed to [$c] so that it can be iterated
--- in-order
local function countLine(c, l, line, pushl)
  local r = c[line]
  if     r == nil   then c[line] = l; if pushl then push(c, line) end
  elseif r ~= false then c[line] = false end
end

--- return lists of line numbers which are unique in both [$b] and [$c],
--- ordered by when the appear in b.
local uniqueMatches = function(bLines, cLines, b, b2, c, c2) --> bList, cList
  local bcount, ccount = {}, {}
  for i=b,b2 do countLine(bcount, i, bLines[i], true) end
  for i=c,c2 do countLine(ccount, i, cLines[i]) end
  local bl, cl = {}, {}
  for _, line in ipairs(bcount) do
    local b, c = bcount[line], ccount[line]
    if b and c then push(bl, b); push(cl, c); end
  end
  return bl, cl
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
local patienceLIS = function(mb, mc) --> bList, cList
  local stacks = {}
  local prev, c, i = {}
  for mi, b in ipairs(mb) do
    i = findLeftStack(stacks, mc, mc[mi])
    if i > 0 then prev[mi] = stacks[i] end
    stacks[i+1] = mi
  end
  local mi = stacks[#stacks]; if not mi then return end
  local b, c = {}, {}
  while prev[mi] do push(b, mb[mi]); push(c, mc[mi]); mi = prev[mi] end
  push(b, mb[mi]); push(c, mc[mi])
  return b, c
end

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

Diff._calc = function(d, b, b2, c, c2)
  local bSt, b2St = b, b2
  local cSt, c2St = c, c2 -- for unchanged top bot lines
  b,  c  = skipEqLinesTop(d.b, d.c, b, b2, c, c2)
  b2, c2 = skipEqLinesBot(d.b, d.c, b, b2, c, c2)
  assert((c - cSt) == (b - bSt))

  local di
  if c > cSt then di = d.di + 1; d.noc[di] = c - cSt; d.di = di end
  local bl, cl = patienceLIS(uniqueMatches(d.b, d.c, b, b2, c, c2))
  if not bl or #bl == 0 then
    local rm, ad = b2 - b + 1, c2 - c + 1
    if rm == 0 and ad == 0 then -- skip
    else
      di = d.di + 1; d.di = di
      if rm > 0 then d.rem[di] = rm end
      if ad > 0 then d.add[di] = ad end
    end
    return
  end

  local bNext, cNext
  for i=#bl,0,-1 do
    local bm = bl[i]
    if bm then bNext, cNext = bm-1, cl[i]-1
    else       bNext, cNext = b2, c2 end
    d:_calc(b, bNext, c, cNext)
    if not bm then break end
    local cm = cl[i]
    di = d.di + 1; d.noc[di], d.di = 1, di
    b, c = bm + 1, cm + 1
  end
  c2 = c2 + 1 -- c2:c2St are unchanged lines (bot)
  if c2 <= c2St then di = d.di + 1; d.noc[di], d.di = c2St - c2 + 1, di end
end

--- accumulate list[i] = list[i]+list[j], treating 0 as nil
local acc = function(list, i, j)
  local v = (list[i] or 0) + (list[j] or 0)
  if v ~= 0 then list[i] = v end
end

--- compress all like-fields together
Diff._compress = function(d)
  local add, rem, noc, len = d.add, d.rem, d.noc, d.di
  -- scan the items, accumulating into i from j
  local i, j = 1, 1
  local clearj = function() add[j], rem[j], noc[j] = nil, nil, nil end
  while j <= len do
    if j <= i then j = i + 1 end
    if not (noc[i] or add[i] or rem[i]) then -- empty i
      acc(noc, i, j); acc(add, i, j); acc(rem, i, j)
      clearj(); j = j + 1
    elseif noc[i] then -- accumulate nochanges
      if noc[j] then acc(noc, i, j); noc[j] = nil; j = j + 1
      else i = i + 1 end
    else -- accumulate add/rem
      if add[j] or rem[j] then
         acc(add, i, j); acc(rem, i, j)
         clearj(); j = j + 1
      else i = i + 1 end
    end
  end
  d.di = i
  i = i + 1; clear(add, i, len); clear(rem, i, len); clear(noc, i, len)
end

getmetatable(Diff).__call = function(T, linesB, linesC) --> Diff
  local d = mty.construct(T, {
    b=linesB, c=linesC, di=0, noc={}, rem={}, add={}
  })
  d:_calc(1, #linesB, 1, #linesC)
  d:_compress()
  return d
end

local function styleNoc(f, chan, bl, cl)
  f:styled('line', sfmt('% 6i % 6i ', bl, cl))
  f:styled('meta', chan[cl] or '<eof>', '\n')
end

Diff.__fmt = function(d, f)
  local base, chan, noc, add, rem = d.b, d.c, d.noc, d.add, d.rem
  local bl, cl, n, a, r = 1, 1 -- bl=base-line cl=changed-line
  if f.style then for i=1,d.di do
    n = noc[i]
    if n then -- unchanged lines
      if n > 0 then styleNoc(f, chan, bl, cl) end
      bl, cl = bl + n, cl + n
      if n > 1 then styleNoc(f, chan, bl-1, cl-1) end
    else
      a, r = add[i], rem[i]
      if r then -- removed lines
        for l=0,r-1 do
          f:styled('reml', sfmt('% 6i        ', bl+l))
          f:styled('rem', base[bl+l], '\n')
        end
        bl = bl + r
      end
      if a then -- added lines
        for l=0,(a or 0)-1 do
          f:styled('addl', sfmt('% 13i ', cl+l))
          f:styled('add', chan[cl+l], '\n')
        end
        cl = cl + a
      end
    end
  end else for i=1,d.di do
    n = noc[i]
    if n then -- unchanged lines
      for l=0,n-1 do
        f:write(' ', str(bl+l), '\t', str(cl+l), '\t',
                chan[cl+l], '\n')
      end
      bl, cl = bl + n, cl + n
    else
      a, r = add[i], rem[i]
      if r then -- removed lines
        for l=0,r-1 do
          f:write('-', str(bl+l), '\t\t', base[bl+l], '\n')
        end
        bl = bl + r
      end
      if a then -- added lines
        for l=0,(a or 0)-1 do
          f:write('+\t', str(cl+l), '\t', chan[cl+l], '\n')
        end
        cl = cl + a
      end
    end
  end end
end

M._toTest = {
  uniqueMatches = uniqueMatches,
  findLeftStack = findLeftStack,   patienceLIS    = patienceLIS,
  skipEqLinesTop = skipEqLinesTop, skipEqLinesBot = skipEqLinesBot,
}

getmetatable(M).__call = function(_, ...) return Diff(...) end
return M
