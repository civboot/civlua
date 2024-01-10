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
  :field('text', 'string')
  :field('b', 'number'):fdoc"base: orig file.  '+' means added line"
  :field('c', 'number'):fdoc"change: new file. '-' means removed line"
  :new(function(ty_, text, b, c)
    return mty.new(ty_, {text=text, b=b, c=c})
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

local DiffsExtender = setmetatable({
  __call = function(de, ch) -- extend change to diffs
    local chTy, base, diffs = mty.ty(ch), de.base, de.diffs
    if chTy == M.Keep then
      for l = de.bl, de.bl + ch.num - 1 do
        push(diffs, m.Diff(base[l], l, de.cl))
        de.cl = de.cl + 1
      end; de.bl = de.bl + ch.num
    else
      mty.assertf(chTy == M.Change, "changes must be Keep|Change: %s", chTy)
      for _, a in ipairs(ch.add) do
        push(diffs, m.Diff(a, '+', de.cl)); de.cl = de.cl + 1
      end
      for l = de.bl, de.bl + ch.rem - 1 do
        push(diffs, m.Diff(base[l], l, '-'))
      end; de.bl = de.bl + ch.rem
    end
  end
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
local function findAnchor(anchors, base, cl)
  assert(cl > 1);
  local al, al2 = cl - 1, cl - 1 -- start/end of anchor
  local alines = {}
  while al > 0 do
    local line = base[al]; local same = anchors[line]
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

local function baseLines(ch)
  if mty.ty(ch) == M.Keep then return ch.num
  else return ch.rem end
end

local function nextAnchor()

end

M.Patches = mty.doc[[
for patch in Patches(base, changes) do ... end

Create patch (aka cherry pick) iterator from changes
]](setmetatable({
  __call = function(cp) -- iterator
    if cp.ci > #changes then return end
    local ch = changes[ci]; local chTy = mty.ty(ch)
    if chTy == M.Keep then assert(ci == 1); ci, de.cl = ci + 1, cl + ch.num
    else -- not at start, need anchor
      local anchor = assert(findAnchor(anchors, base, cl))
      local ci2, cl2 = ci + 1, cl + baseLines(ch)
      while true do
        local ch2 = changes[ci2]; local chTy2 = mty.ty(ch2)
        if (chTy2 == M.Change) or (ch.num == 1) then
          cl2 = cl2 + baseLines(ch)
        elseif findAnchor(anchors, base, cl2) then
          goto continue
        end
        ci2 = ci2 + 1
      end
      ::continue::
    end
  end,
}, {
  __call = function(ty_, base, changes)
    local anchors = {}; for l, line in ipairs(base) do
      push(ds.getOrSet(anchors, line, ds.emptyTable), l)
    end
    return setmetatable({
      anchors = anchors,
      changes = changes, ci=1
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
