local mty = require'metaty'
local push = table.insert

local M = mty.docTy({}, [[
Patch datatypes and apply function.

This is to enable building diff/patch libraries on top of without needing to
define your own types.
]])

M.Keep = mty.record'patch.Keep':field('num',  'number')
M.Chng = mty.record'patch.Chng'
  :field('rem', 'number')     :fdoc'number of lines to remove'
  :fieldMaybe'add':fdoc'text to add'

M.apply = mty.doc[[
apply(dat, patches, out?) -> {Keep|Chng}

Apply patches to lines data. `out` is used for the output, else a new table.
]](function(dat, patches)
  local l = 1; out = out or {}
  for _, p in ipairs(patches) do
    if mty.ty(p) == M.Keep then
      for i=l, l + p.num - 1 do push(out, assert(dat[i], 'invalid data')) end
      l = l + p.num
    else assert(mty.ty(p) == M.Chng)
      if p.add then for _, a in ipairs(p.add) do push(out, a) end end
      l = l + p.rem
    end
  end
  return out
end)

return M
