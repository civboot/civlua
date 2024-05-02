local pkg = require'pkglib'
local mty = pkg'metaty'
local push = table.insert

------------------------------------------------------------------------
-- Fake: a fake terminal for testing

local FakeTerm = mty.record2'FakeTerm'{
  'h[int]: height', 'w[int]: width',
  'l[int]: line',   'c[int]: column',
}
getmetatable(FakeTerm).__call = function(ty_, h, w)
  local t = setmetatable({}, ty_); FakeTerm.init(t, h, w)
  return t
end

FakeTerm.clear = function(t)
  t:golc(1, 1)
  for l=1, t.h do
    local line = {}; for c=1, t.w do line[c] = '' end
    t[l] = line
  end
end

FakeTerm.init = function(t, h, w)
  t.h, t.w = h, w
  t:clear()
end

FakeTerm.golc = function(t, l, c) t.l, t.c = l, c end
FakeTerm.cleareol = function(t, l, c)
  t:assertLC(l, c)
  local line = t[l]
  for i=c, t.w do line[i] = '' end
end

FakeTerm.__fmt = function(t, f)
  for i, line in ipairs(t) do
    push(f, table.concat(line))
    if i < #t then push(f, '\n') end
  end
end

FakeTerm.size = function(t) return t.h, t.w end

-- set is the main method used.
--
FakeTerm.set = function(t, l, c, char)
  t:assertLC(l, c)
  assert(char); assert(char ~= '')
  t[l][c] = char
end

FakeTerm.start = function() end
FakeTerm.stop = function() end

-- utility
FakeTerm.assertLC = function(t, l, c)
  if 1 > l or l > t.h then error("l OOB: " .. l) end
  if 1 > c or c > t.w then error("c OOB: " .. c) end
end

return FakeTerm
