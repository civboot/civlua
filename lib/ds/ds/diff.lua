local mty = require'metaty'
local push = table.insert

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

---------------------
-- Single Line Diff
-- This type is good for displaying differences to a user.
M.Diff = mty.record'patience.Diff'
  :field('text', 'string')
  :fieldMaybe('b', 'number'):fdoc'base: original file'
  :fieldMaybe('c', 'number'):fdoc'change: new file'
  :new(function(ty_, text, b, c)
    return mty.new(ty_, {text=text, b=b, c=c})
  end)

M.Diff.__tostring = function(di)
 return
   ((not di.b and '+') or (not di.c and '-') or ' ')
   ..nw(di.b)..nw(di.c)..'| '..di.text
end

----------------------
-- Grouped Patch
-- Good for storing and merging changes. Typically a patch will be a list
-- of these types.

M.Keep = mty.record'patch.Keep':field('num',  'number')
M.Change = mty.record'patch.Change'
  :field('rem', 'number')     :fdoc'number of lines to remove'
  :fieldMaybe'add':fdoc'text to add'

M.apply = mty.doc[[
apply(dat, patches, out?) -> lines

Apply patches to base (lines table)
`out` lines table is used for the output, else a new table.
]](function(base, patches, out)
  local l = 1; out = out or {}
  for _, p in ipairs(patches) do
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

return M
