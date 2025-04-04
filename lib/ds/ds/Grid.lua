-- text grid type
local mty = require'metaty'
local ds = require'ds'

local clear = ds.clear
local max = math.max
local push, concat = table.insert, table.concat
local codes, char = utf8.codes, utf8.char

--- ds.Grid: a text grid
--- Grid is a table (rows/lines) of tables (cols). Each column should contain a
--- single unicode character or nil.
local G = mty'ds.Grid' {
  'h [int]: height', 'w [int]: width',
}
getmetatable(G).__call = function(T, t)
  return mty.construct(T, t):clear()
end

--- clear the grid
G.clear = function(g) --> g
  for l=1,g.h do
    local line = g[l] or {}
    clear(line, 1, max(#line, g.w)); assert(next(line) == nil)
    g[l] = line
  end
  clear(g, g.h + 1, #g)
  return g
end

local split = function(s) --> lines
  if type(s) == 'string' then return ds.split(s, '\n')
  else --[[lines]]            return ipairs(s) end
end

--- insert the str|lines into the grid at l.c
--- this handles newlines by inserting at the same column
G.insert = function(g, l, c, str)
  for _l, lstr in split(str) do
    local llen = 0
    local line = g[l]; if not line then return end
    for _, code in codes(lstr) do
      llen = llen + 1
      local lc = c + llen - 1; assert(lc <= g.w, 'line+c too long')
      for i=#line+1,lc-1 do line[i] = ' ' end -- fill spaces
      line[lc] = char(code)
    end
    l = l + 1
  end
end

G.__fmt = function(g, f)
  local h = g.h; for l=1,h-1 do f:write(concat(g[l]), '\n') end
  f:write(concat(g[h]))
end

return G
