-- text grid type
local mty = require'metaty'
local ds = require'ds'

local clear = ds.clear
local max = math.max
local push, concat = table.insert, table.concat
local codes, char = utf8.codes, utf8.char

-- ds.Grid: a text grid
-- Grid is a table (rows/lines) of tables (cols). Each column should contain a
-- single unicode character or nil.
local G = mty'ds.Grid' {
  'h [int]: height', 'w [int]: width',
}
getmetatable(G).__call = function(T, t)
  return mty.construct(T, t):clear()
end

G.clear = function(g)
  for l=1,g.h do
    local line = g[l] or {}
    clear(line, 1, max(#line, g.w))
    g[l] = line
  end
  clear(g, g.h + 1, max(0, #g))
  return g
end

-- insert the str into the grid at l.c
-- this handles newlines by inserting at the same column
G.insert = function(g, l, c, str)
  for _, lstr in ds.split(str, '\n') do
    local llen = 0
    print('!! lstr', l, lstr)
    local line = g[l]
    for _, code in codes(lstr) do
      llen = llen + 1
      local lc = c + llen - 1; assert(lc <= g.w, 'line+c too long')
      print('!! chr', char(code), lc)
      for i=#line+1,lc-1 do line[i] = ' ' end -- fill spaces
      line[lc] = char(code)
    end
    l = l + 1
  end
end

G.__fmt = function(g, fmt)
  local h = g.h; for l=1,h-1 do
    push(fmt, concat(g[l])); push(fmt, '\n')
  end
  push(fmt, concat(g[h]))
end

return G
