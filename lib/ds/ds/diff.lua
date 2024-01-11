local mty = require'metaty'
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
    return mty.new(ty_, {b=b, c=c, text=text})
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
  __call = function(de, ch) -- extend change to diffs
    local chTy, base, diffs = mty.ty(ch), de.base, de.diffs
    if chTy == M.Keep then
      for l = de.bl, de.bl + ch.num - 1 do
        push(diffs, m.Diff(l, de.cl, base[l]))
        de.cl = de.cl + 1
      end; de.bl = de.bl + ch.num
    else
      mty.assertf(chTy == M.Change, "changes must be Keep|Change: %s", chTy)
      for _, a in ipairs(ch.add) do
        push(diffs, m.Diff('+', de.cl, a)); de.cl = de.cl + 1
      end
      for l = de.bl, de.bl + ch.rem - 1 do
        push(diffs, m.Diff(l, '-', base[l]))
      end; de.bl = de.bl + ch.rem
    end
  end,
}, { __call = function(ty_, base) -- create DiffsExtender
  return setmetatable({diffs={}, base=base, bl=1, cl=1}, ty_)
end})

M.toDiff = mty.doc[[
toDiff(base, changes) -> diffs

Convert Changes to Diffs with full context
]](function(base, changes)
  local de = DiffsExtender(base)
  for _, ch in ipairs(changes) do de(ch) end
  return diffs
end)

-- find a suitable anchor for a change starting at cl
local function findAnchor(base, baseLineMap, cl)
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

local function anchorEnd(base, ch, cl)
  return (cl + changeLen(ch) >= #p.base)
end

M.Patches = mty.doc[[
Create patch (aka cherry pick) iterator from changes.

Example:
  for patch in Patches(base, changes) do ... end
]](setmetatable({
  __call = function(p) -- iterator
    local de, changes = p.de, p.changes
    if p.ci > #changes then return end
    assert(ds.isEmpty(de.diffs))
    local ch = changes[p.ci]
    if mty.ty(ch) == M.Keep then
      if p.ci == #changes then p.ci = p.ci + 1; return end
      -- discard first Keep
      assert(p.ci == 1, 'internal error, unexpected Keep')
      p.ci = p.ci + 1; de(changes[1]); de.diffs = {}
      ch = changes[p.ci]
    end
    local a, ci1, ci2 = groupChanges(p, p.ci)
    assert(ci1, "internal error: anchor not possible")
    -- push preceeding Keep then keep only anchor
    assert(p.ci == ci1 - 1)
    de(changes[p.ci]); p.ci = p.ci + 1
    if     a == 0  then de.diffs = {M.DiffSoF}
    elseif a == -1 then de.diffs = {M.DiffEoF}
    else
      local diffs = {} -- keep a[2]-a[1] diffs
      for i = #de.diffs - (a[2] - a[1]), #de.diffs do
        local d = de.diffs[i]
        assert(type(d.b == 'number') and type(d.c) == 'number')
        push(diffs, d)
      end
      de.diffs = diffs
    end
    while p.ci <= ci2 do de(changes[p.ci]); p.ci = p.ci + 1 end
    assert(not ds.isEmpty(de.diffs))
    local diffs = de.diffs; de.diffs = {}
    return diffs
  end,

  -- get the change indexes to include in the diff item
  -- Groups changes until a change with an independant anchor is found.
  groupChanges = function(p, ci)
    local ch, start, cl = p.changes[ci], ci, p.de.cl
    if (cl == 1)                 then return 0,  ci, ci end
    if anchorEnd(p.base, ch, cl) then return -1, ci, ci end
    local a = {findAnchor(p.base, p.baseLineMap, cl)}; assert(a[1])

    local minL = 1
    while ci <= #p.changes do
      ch = p.changes[ci]; local chTy = mty.ty(ch)
      if chTy == M.Keep then minL = cl; cl = cl + ch.num
      else assert(chTy == M.Change)
        if anchorEnd(p.base, ch, cl) then return a, start, ci - 1 end
        if cl > minL + 1 then -- at least 2 line anchor possible
          local al = findAnchor(p.base, p.baseLineMap, cl)
          if al <= minL              then return a, start, ci - 1 end
        end
        cl = cl + ch.rem; minL = cl
      end
      ci = ci + 1
    end
    error'unreachable'
  end,

}, {
  __call = function(ty_, base, changes)
    local baseLineMap = {}; for l, line in ipairs(base) do
      push(ds.getOrSet(baseLineMap, line, ds.emptyTable), l)
    end
    return setmetatable({
      baseLineMap = baseLineMap,
      changes = changes, ci=1,
      de = DiffsExtender(base),
    }, ty_)
  end
}))

M.toPatch = mty.doc[[
]](function(base, changes)
  local ci, de, patches = 1, 1, DiffsExtender(base), {}
  -- de.diffs has the CURRENT patch with context/etc
  while ci < #changes do
  end
end

)

return M
