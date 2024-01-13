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

-- TODO: I want to use this when applying patches
M.normalize = mty.doc[[normalize a line for comparing (anchoring).
This just squashes and trims the end.]]
(function(s) return ds.squash(ds.trimEnd(s)) end)

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
        if base then push(p.rem, d.text)
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

M.createAnchorTop = function(base, l, aLen)
  local a = {}; if l < 1 then return a end
  for l = l, 1, -1 do
    if aLen <= 0 then break end
    local line = base[l]; push(a, M.Diff(l, '@', line))
    if ds.trim(line) ~= '' then aLen = aLen - 1 end
  end
  return ds.reverse(a)
end

M.createAnchorBot = function(base, l, aLen)
  local a = {}; for l, line in ds.islice(base, l) do
    if aLen <= 0 then break end
    push(a, M.Diff(l, '@', line))
    if ds.trim(line) ~= '' then aLen = aLen - 1 end
  end
  return a
end

M.Picks = mty.doc[[
Create picks (aka cherry picks) iterator from changes.
These can then be applied to a new base using vcds.patch(base, picks)

Each "pick" is a list of Diffs which are anchored by the lines
above and below (unless they are start/end of file).
]](setmetatable({
  __index = function(p, k) return getmetatable(p)[k] end,
  __call = function(p) -- iterator
    local de, changes, aLen = p.de, p.changes, p.set.anchorLen
    mty.pntf('?? Picks(ci=%s de{cl=%s cl=%s})', p.ci, de.cl, de.cl)
    if p.ci > #changes then return end
    assert(ds.isEmpty(de.diffs))

    local ci, endci = p:groupChanges(p.ci)
    while p.ci < ci do de(changes[p.ci]); p.ci = p.ci + 1 end -- discard
    de.diffs = M.createAnchorTop(de.base, de.bl - 1, aLen)
    while p.ci <= endci do de(changes[p.ci]); p.ci = p.ci + 1 end -- changes
    ds.extend(de.diffs, M.createAnchorBot(de.base, de.bl, aLen))
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

}, {
  __call = function(ty_, base, changes, set)
    set = set or {}
    set.anchorLen = set.anchorLen or 3
    return setmetatable({
      changes = changes, ci=1,
      de = DiffsExtender(base),
      set=set,
    }, ty_)
  end
}))

local function checkAnchor(iter, base, bl)
  local bline; for _, aline in table.unpack(iter) do
    if ds.trim(aline) == '' then              goto continue end
    bline = base[bl]; if not bline then return false end
    if ds.trim(bline) == '' then bl = bl + 1; goto continue end
    if not mty.eq(aline, bline) then return false end
    bl = bl + 1; ::continue::
  end
  return true
end

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
      if checkAnchor({iterFn(alines)}, base, bl) then
        found, fbl = found + 1, bl
      end
    end
    if found == 1 then return fbl, #alines end
  end
end)

M.Patch = mty.record'vcds.Patch'
  :fieldMaybe('error', 'string')
  :fieldMaybe('bl',    'number')

-- return isSoF, anchors
M.pickAnchorsTop = function(pick)
  local anchors = {}; for _, d in ipairs(pick) do
    if d.c ~= '@' then break end; push(anchors, d)
  end
  return pick[1].b == 1, anchors
end

-- return isEoF, anchors
M.pickAnchorsBottom = function(base, pick)
  local anchors = {}; for _, d in ds.ireverse(pick) do
    if d.c ~= '@' then break end; push(anchors, d)
  end
  return pick[#pick].b == #base, ds.reverse(anchors)
end

local function patchError(pick, ...)
  local p = M.Patch{error=sfmt(...)}
  ds.extend(p, pick)
  return p
end
--[[
Create a patch item from a pick

At it's most basic it would just be:
• find line position via top and/or bottom anchor. We want at least 2 lines
• convert pick to change. Walk the text applying the change.

There are some strategies to fix common anchor misses:
• If an anchor is missing, the nearby change can be used instead. Use either
  the removed or added lines. For instance, if we are supposed to remove lines
  then try and find them. Conversely if the patch was already applied then the
  supposed-to-be added lines will already be there!
• When adding, existing identical text is okay.
• When removing, missing text is okay as long as it's followed by an anchor of
  some kind
• Keep lines act as an anchor (for above) but are otherwise not required - they
  are "free" to change or be removed. If they are missing then the algorithm will
  try to continue the change with or without them (dynamic programming)
* empty lines are entirely ignored and are not considered an anchor
]]
M.createPatch = function(base, pick)
  mty.pnt('?? createPatch', pick)
  local first, last = pick[1], pick[#pick]
  local isSof, topA = M.pickAnchorsTop(first)
  local isEof, botA = M.pickAnchorsBottom(base, last)
  local top, topLines = M.findAnchor(base, lineMap, topA, true)
  local bot, botLines = M.findAnchor(base, lineMap, botA, false)
  top = (isSof and 1)           or (top and (top + topLines))
  bot = (isEof and (#base + 1)) or (bot and (bot + botLines))
  mty.pntf('?? top=%s bot=%s', top, bot)
  if not top then return patchError(pick,
    '%s anchor not found',
    (not top and not bot) and 'top and bot' or 'top'
  )end
  local bl = top
  -- for _, ch in M.toChanges(
end


return M
