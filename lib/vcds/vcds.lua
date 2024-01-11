-- vsds: version control data structures (and algorithms)
local pkg = require'pkg'
local mty = pkg'metaty'
local ds  = pkg'ds'
local push, sfmt = table.insert, string.format

local function nw(n) -- numwidth
  if n == nil then return '        ' end
  n = tostring(n); return n..string.rep(' ', 8-#n)
end

local M = mty.docTy({}, [[
Version control data structures and algorithms.
]])
M.ADD = '+'
M.REM = '-'
M.ANC = '@'

---------------------
-- Single Line Diff
-- This type is good for displaying differences to a user.
M.Diff = mty.record'patience.Diff'
  :field('b', 'number'):fdoc"base: orig file.  '+'=added"
  :field('c', 'number'):fdoc"change: new file. '-'=removed, '@'=anchor (ignore)"
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
M.Keep.len = function(k) return k.num end

M.Change = mty.record'patch.Change'
  :field'rem':fdoc'removed lines. Can be number or list'
  :fieldMaybe'add':fdoc'text to add'
M.Change.len = function(ch)
  return (type(ch.rem) == 'number') and ch.rem or #ch.rem
end

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

M.toChanges = function(diffs, base)
  local changes, p = {}, nil
  for _, d in ipairs(diffs) do
    if d.c == M.ANCHOR then -- skip
    elseif d.b ~= M.ADD and d.c ~= M.REM then -- keep
      if not p or mty.ty(p) ~= M.Keep then push(changes, p); p = M.Keep{num=0} end
      p.num = p.num + 1
    else
      if not p or mty.ty(p) ~= M.Change then
        push(changes, p); p = M.Change{rem=base and {} or 0}
      end
      if d.b == M.ADD then pushAdd(p, d.text)
      else assert(d.c == M.REM)
        if base then push(p.rem, base[d.b])
        else         p.rem = p.rem + 1 end
      end
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
      for l = de.bl, de.bl + ch:len() - 1 do
        push(diffs, M.Diff(l, '-', base[l]))
      end; de.bl = de.bl + ch:len()
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

M.toPatch = mty.doc[[
A "patch" is a list containing groups of Diff.

Each group starts and ends with a few Diff{c='@', ...} anchors (except if the change
is at the start or end of the file, respectively). These are used in M.patch to find
where the respective changes should be made.
]](function(base, changes)
  local pchs = {}; for p in M.Patches(base, changes) do push(pchs, p) end
  return pchs
end)

-- iterFn = ds.ireverse to find the top, ipairs to find bottom.
M.findAnchor = mty.doc[[
findAnchor(base, lineMap, anchors: {Diff}, above: boolean)
  -> line, anchorTextLines

Find the actual anchor by searching for uniqueness in the anchors:
* above=true:  find above (search up)
* above=false: find below (search down)
]](function(base, lineMap, anchors, above)
  mty.pntf('?? findAnchor len=%s above=%s', #anchors, above)
  local iterFn = above and ds.ireverse or ipairs
  local alines = {}
  for ai, anchor in iterFn(anchors) do
    local bls = lineMap[anchor.text]; if not bls then return end
    mty.pnt('?? find anchor loop:', ai, anchor, bls)
    if #bls == 1 then
      -- in this case below needs to subtract previous lines
      -- in `found` case, it is comparing correctly so no need.
      return bls[1] - (above and 0 or #alines), #alines + 1
    end
    push(alines, anchor.text)
    -- see if the whole anchor is unique
    local found, fbl = 0; for _, bl in ipairs(bls) do
      bl = above and bl or (bl - #alines + 1)
      mty.pnt('?? comparing for:', alines, ':with:',
              ds.itable{ds.islice(base, bl, bl + #alines - 1)},
              ':at', bl, ':found:', found)
      if ds.ieq({iterFn(alines)},
                {ds.islice(base, bl, bl + #alines - 1)}) then
        found, fbl = found + 1, bl
      end
    end
    if found == 1 then return fbl, #alines end
  end
end)

M.Patch = mty.record'vcds.Patch'
  :fieldMaybe('error', 'string')
  :fieldMaybe('bl',    'number')
  :field'changes'

-- return isSoF, anchors
M.diffsAnchorsTop = function(diffs)
  local anchors = {}; for _, d in ipairs(diffs) do
    if d.c ~= '@' then break end; push(anchors, d)
  end
  return diffs[1].b == 1, anchors
end

-- return isEoF, anchors
M.diffsAnchorsBottom = function(base, diffs)
  local anchors = {}; for _, d in ds.ireverse(diffs) do
    if d.c ~= '@' then break end; push(anchors, d)
  end
  return diffs[#diffs].b == #base, ds.reverse(anchors)
end


-- Patcher: type to handle patches
-- fields: base, pi (patch-index)

M.patch = mty.doc[[
patch(base, patches) -> changes, errors
]]
(function(base, patches)
  local lineMap = ds.lines.map(base)
  local changeMap, errors = {}, {}
  for _, patch in ipairs(patches) do
    local first, last = patch[1], patch[#patch]
    local isSof, topA = M.diffsAnchorsTop(first)
    local isEof, botA = M.diffsAnchorsBottom(base, last)
    local startl, endl
    local top, topLines = M.findAnchor(base, lineMap, topA, true)
    local bot, botLines = M.findAnchor(base, lineMap, botA, false)

    local p = {
      base=base, lineMap=lineMap,
      chs = M.toChanges(patch),
      top = top or (isSof and 1)           or nil,
      bot = bot or (isEof and (#base + 1)) or nil,
    }

  end

end)


return M
