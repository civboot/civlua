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
local clear = ds.clear

M.NOC = ' '
M.ADD = '+'
M.REM = '-'
local NOC, ADD, REM = M.NOC, M.ADD, M.REM

--- indexed results of diff, not typically used directly.
local _IDiff = mty'IDiff' {
}

--- the result of a line-based diff algorithm that can be
--- shown and iterated on
M.Diff2 = mty'Diff' {
  'b [lines]: base, aka original lines',
  'c [lines]: change, aka new lines',
  'di [int]: len of noc/rem/add',
  'noc [ints]: nochange range (in both)',
  'rem [ints]: removed from b',
  'add  [ints]: added from c',
}

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
  local b, c = {}, {}
  while prev[mi] do push(b, mb[mi]); push(c, mc[mi]); mi = prev[mi] end
  push(b, mb[mi]); push(c, mc[mi])
  return _BC{b=b, c=c}
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

  if c > cSt then u[di] = c - cSt; di = di + 1 end
  addIs(t, ' ', bSt, cSt, c-1) -- unchanged lines (top)
  local matches = uniqueMatches(linesB, linesC, b, b2, c, c2)
  local lis = patienceLIS(matches)
  if not lis or #lis.b == 0 then
    for i=c,c2 do push(t, DiffI(ADD, nil, i)) end
    for i=b,b2 do push(t, DiffI(REM, i, nil)) end
    return
  end

  local bl, cl, bNext, cNext = lis.b, lis.c
  for i=#bl,0,-1 do
    local bm = bl[i]
    if bm then bNext, cNext = bm-1, cl[i]-1
    else       bNext, cNext = b2, c2 end
    diffI(t, linesB, linesC, b, bNext, c, cNext)
    if not bm then break end
    local cm = cl[i]
    push(t, DiffI(' ', bm, cm))
    b, c = bm + 1, cm + 1
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

M.Diff2._calc = function(d, b, b2, c, c2)
  local bSt, b2St = b, b2
  local cSt, c2St = c, c2 -- for unchanged top bot lines
  b,  c  = skipEqLinesTop(d.b, d.c, b, b2, c, c2)
  b2, c2 = skipEqLinesBot(d.b, d.c, b, b2, c, c2)
  assert((c - cSt) == (b - bSt))

  local di
  if c > cSt then di = d.di + 1; d.noc[di] = c - cSt; d.di = di end
  local matches = uniqueMatches(d.b, d.c, b, b2, c, c2)
  local lis = patienceLIS(matches)
  if not lis or #lis.b == 0 then
    local rm, ad = b2 - b + 1, c2 - c + 1
    if rm == 0 and ad == 0 then -- skip
    else
      di = d.di + 1; d.di = di
      if rm > 0 then d.rem[di] = rm end
      if ad > 0 then d.add[di] = ad end
    end
    return
  end

  local bl, cl, bNext, cNext = lis.b, lis.c
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

--- compress all like-fields together
M.Diff2._compress = function(d)
  local di, add, rem, noc, len = 1, d.add, d.rem, d.noc, d.di
  for i=1,d.di do
    if noc[di] or noc[di+1] then
      if noc[di] and noc[di+1] then
        assert(not add[di] and not add[di+1]
           and not rem[di] and not rem[di+1])
        noc[i] = noc[di] + noc[di+1]
        add[i], rem[i] = nil, nil
        di = di + 2
        goto continue
      end
    elseif (add[di] and 1 or 0) + (add[di+1] and 1 or 0)
         + (rem[di] and 1 or 0) + (rem[di+1] and 1 or 0)
         >= 2 then
      assert(not (noc[di] or noc[di+1]))
      add[i] = (add[di] or 0) + (add[di+1] or 0)
      rem[i] = (rem[di] or 0) + (rem[di+1] or 0)
      noc[i] = nil
      if add[i] == 0 then add[i] = nil end
      if rem[i] == 0 then rem[i] = nil end
      di = di + 2
      goto continue
    end
    add[i], rem[i], noc[i] = add[di], rem[di], noc[di]
    di = di + 1
    ::continue::
  end
  d.di = di - 1
  clear(d.add, di, len); clear(d.rem, di, len); clear(d.noc, di, len)
end

M.diff2 = function(linesB, linesC)
  local d = M.Diff2{b=linesB, c=linesC, di=0, noc={}, rem={}, add={}}
  d:_calc(1, #linesB, 1, #linesC)
  d:_compress()
  return d
end

M._forTest = {
  uniqueMatches = uniqueMatches,
  findLeftStack = findLeftStack,   patienceLIS   = patienceLIS,
  skipEqLinesTop = skipEqLinesTop, skipEqLinesBot = skipEqLinesBot,
  _BC = _BC,
}

getmetatable(M).__call = function(_, ...) return diff(...) end
return M
