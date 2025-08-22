-- text grid type
local mty = require'metaty'
local ds = require'ds'
local fmt = require'fmt'

local clear = ds.clear
local max = math.max
local push, concat = table.insert, table.concat
local codes, char = utf8.codes, utf8.char
local assertf = fmt.assertf

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

--- Insert the str into the Grid.
--- Any newlines will be insert starting at column c.
---
--- This will automatically fill [1,c-1] with spaces, but will
--- NOT clear any data after the insert text, meaning it is
--- essentially a replace.
--- FIXME: considere renaming to replace... or something.
G.insert = function(g, l, c, str)
  for _, sline in split(str) do -- line from string
    local row = g[l]; if not row then return end
    for i=#row+1, c-1 do row[i] = ' ' end -- fill pre-column space
    local lc = c -- unicode column within line
    for _, uchr in codes(sline) do
      row[lc] = char(uchr); lc = lc + 1
    end
    l = l + 1
  end
end

G.__fmt = function(g, f)
  local h = g.h; for l=1,h-1 do f:write(concat(g[l]), '\n') end
  f:write(concat(g[h]))
end

return G
