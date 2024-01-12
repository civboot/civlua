local pkg = require'pkg'
local mty = require'metaty'
local ds  = require'ds'
local push = table.insert
local sfmt = string.format

local function nw(n) -- numwidth
  if n == nil then return '        ' end
  n = tostring(n); return n..string.rep(' ', 8-#n)
end

local M = mty.docTy({}, [[
Types and functions for diff and patch.

Types
* Diff: single line diff with info of both base and change
* Keep/Change: a list creates a "patch" to a base
]])
M.ADD = '+'
M.REM = '-'

---------------------
-- Single Line Diff
-- This type is good for displaying differences to a user.
M.Diff = mty.record'patience.Diff'
  :field('b', 'number'):fdoc"base: orig file.  '+' means added line"
  :field('c', 'number'):fdoc"change: new file. '-' means removed line"
  :field('text', 'string')
  :new(function(ty_, b, c, text)
    return mty.new(ty_, {b=b, c=c, text=assert(text)})
  end)

M.Diff.__tostring = function(di)
  return string.format("%4s %4s|%s", di.b, di.c, di.text)
end

local function pushAdd(ch, text)
  if not ch.add then ch.add = {} end; push(ch.add, text)
end

----------------------
-- ChangeList composed of Keep and Change directives
-- This is how diffs are often serialized

M.Keep = mty.record'patch.Keep':field('num',  'number')
M.Change = mty.record'patch.Change'
  :field('rem', 'number')     :fdoc'number of lines to remove'
  :fieldMaybe'add':fdoc'text to add'

M.apply = mty.doc[[
apply(dat, changes, out?) -> out

Apply changes to base (TableLines)
`out` is used for the output, else a new table.
]](function(base, changes, out)
  local l = 1; out = out or {}
  for _, p in ipairs(changes) do
    local pty = mty.ty(p)
    if pty == M.Keep then
      for i=l, l + p.num - 1 do push(out, assert(base[i], 'base OOB')) end
      l = l + p.num
    else
      mty.assertf(pty == M.Change, 'patch type must be Keep|Change: %s', pty)
      if p.add then for _, a in ipairs(p.add) do push(out, a) end end
      l = l + p.rem
    end
  end
  return out
end)

----------------------
-- Conversion

M.toChanges = function(diffs)
  local changes, p = {}, nil
  for _, d in ipairs(diffs) do
    if d.b ~= M.ADD and d.c ~= M.REM then -- keep
      if not p or mty.ty(p) ~= M.Keep then push(changes, p); p = M.Keep{num=0} end
      p.num = p.num + 1
    else
      if not p or mty.ty(p) ~= M.Change then push(changes, p); p = M.Change{rem=0} end
      if d.b == M.ADD                   then pushAdd(p, d.text)
      else assert(d.c == M.REM);             p.rem = p.rem + 1 end
    end
  end
  if p then push(changes, p) end
  return changes
end

M.DiffSoF = M.Diff('^', 0,  '') -- start of file
M.DiffEoF = M.Diff('$', -1, '') -- end of file

local DiffsExtender = setmetatable({
  __call = function(de, ch, keepMax) -- extend change to diffs
    local chTy, base, diffs = mty.ty(ch), de.base, de.diffs
    if chTy == M.Keep then
      for l = de.bl, de.bl + ch.num - 1 do
        push(diffs, M.Diff(l, de.cl, base[l]))
        de.cl = de.cl + 1
      end; de.bl = de.bl + ch.num
    else
      mty.assertf(chTy == M.Change, "changes must be Keep|Change: %s", chTy)
      for _, a in ipairs(ch.add) do
        push(diffs, M.Diff('+', de.cl, a)); de.cl = de.cl + 1
      end
      for l = de.bl, de.bl + ch.rem - 1 do
        push(diffs, M.Diff(l, '-', base[l]))
      end; de.bl = de.bl + ch.rem
    end
  end,
}, { __call = function(ty_, base) -- create DiffsExtender
  return setmetatable({diffs={}, base=base, bl=1, cl=1}, ty_)
end})

M.toDiffs = mty.doc[[
toDiff(base, changes) -> diffs

Convert Changes to Diffs with full context
]](function(base, changes)
  local de = DiffsExtender(base)
  for _, ch in ipairs(changes) do de(ch) end
  return de.diffs
end)

-- find a suitable anchor for a change above base[cl]
function M._findAnchor(base, baseLineMap, cl)
  assert(cl > 1);
  local al, al2 = cl - 1, cl - 1 -- start/end of anchor
  local alines = {}
  while al > 0 do
    local line = base[al]; local same = baseLineMap[line]
    if same[1] == al then
      -- first of it's kind. Add a line if possible for extra context
      return math.max(1, al-1), al2
    end
    push(alines, line)
    for _, sl in ipairs(same) do
      if sl > al  then goto continueAl end -- none found
      -- check if any lines below the sameLine are different
      for i, line in ds.islice(alines, 2) do
        if line ~= base[sl + (#alines - i)] then return al, al2 end
      end
    end
    ::continueAl::; al = al - 1
  end
end

local function changeLen(ch)
  if mty.ty(ch) == M.Keep then return ch.num
  else return ch.rem end
end

M.Patches = mty.doc[[
Create patch (aka cherry pick) iterator from changes.

Example:
  for patch in Patches(base, changes) do ... end
]](setmetatable({
  __index = function(p, k) return getmetatable(p)[k] end,
  __call = function(p) -- iterator
    local de, changes, aLen = p.de, p.changes, p.set.anchorLen
    mty.pntf('?? Patches(ci=%s de{cl=%s cl=%s})', p.ci, de.cl, de.cl)
    if p.ci > #changes then return end
    assert(ds.isEmpty(de.diffs))

    local ci, endci = p:groupChanges(p.ci)
    while p.ci < ci do de(changes[p.ci]); p.ci = p.ci + 1 end -- discard
    de.diffs = {}; p:anchorLines(de.bl - aLen, de.bl - 1)     -- anchor start
    while p.ci <= endci do de(changes[p.ci]); p.ci = p.ci + 1 end -- changes
    p:anchorLines(de.bl, de.bl + aLen - 1)                    -- anchor end
    local diffs = de.diffs; de.diffs = {}
    return diffs

    -- local ch = changes[p.ci]
    -- mty.pnt('?? Patches first ch:', ch)
    -- if mty.ty(ch) == M.Keep then
    --   if p.ci == #changes then p.ci = p.ci + 1; return end -- EoF
    --   de(ch); p.ci = p.ci + 1; ch = changes[p.ci]
    -- else
    --   assert(p.ci == 1, 'Change w/out Keep')
    --   assert(cl == 1)
    -- end
    -- mty.pnt('?? Patches second ch:', ch)
    -- assert(mty.ty(ch) == M.Change)
    -- local a, ci1, ci2 = p:groupChanges(p.ci, cl)
    -- assert(ci1, "internal error: anchor not possible")
    -- if     a == 0  then de.diffs = {M.DiffSoF}
    -- elseif a == -1 then de.diffs = {M.DiffEoF}
    -- else
    --   local diffs = {} -- keep a[2]-a[1] diffs
    --   local dlow = math.max(1, #de.diffs - (a[2] - a[1]))
    --   mty.pntf('?? diffs a=%s dlow=%s #diffs=%s', mty.fmt(a), dlow, #de.diffs)
    --   for i =dlow, #de.diffs do
    --     local d = de.diffs[i]
    --     mty.pntf('?? diffs i=%s, d=%s', i, d)
    --     assert(type(d.b == 'number') and type(d.c) == 'number')
    --     push(diffs, d)
    --   end
    --   de.diffs = diffs
    -- end
    -- while p.ci <= ci2 do de(changes[p.ci]); p.ci = p.ci + 1 end
    -- assert(not ds.isEmpty(de.diffs))
    -- local diffs = de.diffs; de.diffs = {}
    -- mty.pnt('?? Patches() ->', diffs)
    -- mty.pntf('?? end(ci=%s de{bl=%s cl=%s})', p.ci, de.bl, de.cl)
    -- return diffs
  end,

  -- Get which changes to include in a patch group.
  -- A group is a series of patches with Keep.num < anchorLen (default=3)
  -- between them.
  groupChanges = function(p, ci)
    local len, aLen = #p.changes, p.set.anchorLen
    while ci <= len and mty.ty(p.changes[ci]) == M.Keep do
      ci = ci + 1
    end
    local starti = ci; for ci, ch in ds.islice(p.changes, ci) do
      local chTy = mty.ty(ch)
      if ci == len then
        if chTy == M.Keep then ci = ci - 1 end
        return starti, ci
      end
      if (chTy == M.Keep) and (ch.num >= aLen) then
        return starti, ci - 1 end
    end; error'unreachable'
  end,

  anchorLines = function(p, bl, blEnd)
    local de = p.de; for bl = math.max(1, bl), math.min(#de.base, blEnd) do
      push(de.diffs, M.Diff(bl, '@', de.base[bl]))
    end
  end,
}, {
  __call = function(ty_, base, changes, set)
    set = set or {}
    set.anchorLen = set.anchorLen or 3
    local baseLineMap = ds.lines.map(base)
    return setmetatable({
      baseLineMap = baseLineMap,
      changes = changes, ci=1,
      de = DiffsExtender(base),
      set=set,
    }, ty_)
  end
}))

M.toPatch = function(base, changes)
  local pchs = {}; for p in M.Patches(base, changes) do push(pchs, p) end
  return pchs
end

return M
