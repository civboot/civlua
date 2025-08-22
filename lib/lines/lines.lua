--- lines module, when called splits a string into lines.
---   [$require'lines'(text) -> table of lines]
---
--- sub-modules include several data structures with more performant
--- mechanisms to insert/remove/etc based on real-world workloads
--- (i.e. editor, parser, etc)
local M = mod and mod'lines' or {}

local mty = require'metaty'
local ds  = require'ds'
local push, pop = table.insert, table.remove
local concat    = table.concat
local max, min, bound = math.max, math.min, ds.bound
local srep = string.rep
local sort2 = ds.sort2
local rawsplit = mty.rawsplit

local set, get, inset = ds.set, ds.get, ds.inset

M.CMAX = 999
M.CHUNK = 0x4000 -- 16KiB

local new = function(_, text, index)
  local t = {}
  for _, line in rawsplit, text, {'\n', index or 1} do
    push(t, line)
  end; return t
end
setmetatable(M, {__call=new})

--- concat strings and return lines table
M.args = function(...) --> lines
  local len = select('#', ...)
  if     len == 0 then return {}
  elseif len == 1 then return new(nil, select(1, ...))
  else                 return new(nil, concat{...}) end
end
local args = M.args

--- join a table with newlines
M.join = function(t) return concat(t, '\n') end --> string
local join = M.join

local sinsert = function (s, i, v) return s:sub(1, i-1)..v..s:sub(i) end

--- insert string at l, c
---
--- Note: this is NOT performant (O(N)) for large tables.
--- See: lib/rebuf/gap.lua (or similar) for handling real-world workloads.
M.inset = function(t, s, l,c) --> nil
  inset(t, l, M(sinsert(get(t, l) or '', c or 1, s)), 1)
end

--- Address lines span via either (l,l2) or (l,c, l2,c2)
local function span(l, c, l2, c2)
  if      l2 and c2 then return l, c, l2, c2    end --(l,c, l2,c2)
  if not (l2 or c2) then return l, nil, c, nil  end --(l,   l2)
  if not (c  or c2) and (l and l2) then
    return l, nil, l2, nil
  end --(l,   l2)
  error'span must be 2 or 4 indexes: (l, l2) or (l, c, l2, c2)'
end
M.span = span

--- sort the span
M.sort = function(...) --> l1, c1, l2, c2
  local l, c, l2, c2 = span(...)
  if l > l2 then l, c, l2, c2 = l2, c2, l, c
  elseif c and (l == l2) and (c > c2) then c, c2 = c2, c end
  return l, c, l2, c2
end

local function _lsub(sub, slen, t, ...)
  local l, c, l2, c2 = span(...)
  local len = #t
  local lb, lb2 = ds.bound(l, 1, len), ds.bound(l2, 1, len+1)
  if lb  > l  then c = 1 end
  if lb2 < l2 then c2 = nil end -- EoL
  l, l2 = lb, lb2
  local s = {} -- s is sub
  for i=l,l2 do push(s, get(t, i)) end
  if    nil == c then -- only lines
    if l2 < len then push(s, '') end -- newline
  elseif #s == 0 then s = '' -- empty
  elseif l == l2 then
    assert(1 == #s); local line = s[1]
     s = sub(line, c, c2)
    if c2 > slen(line) and l2 < len then s = s..'\n' end
  else
    local last = s[#s]
    s[1] = sub(s[1], c); s[#s] = sub(last, 1, c2)
    if c2 > #last and l2 < len then push(s, '') end
    s = join(s)
  end
  return s
end

M.sub  = function(...) return _lsub(string.sub, string.len, ...) end
M.usub = function(...) return _lsub(ds.usub,     utf8.len,   ...) end

--- create a table of lineText -> {lineNums}
M.map = function(lines) --> table
  local map = {}; for l, line in ipairs(lines) do
    push(ds.getOrSet(map, line, ds.emptyTable), l)
  end
  return map
end

--- bound the line/col for the lines table.
--- This will automatically convert negatives indexes to positive,
--- where [$-1] is the last item.
M.bound = function(t, l, c, len, line) --> l, c
  if l < 0 then l = #t + l + 1 end
  l = bound(l, 1, max(1, len or #t))
  if not c then return l end
  line = line or get(t, l) or ''
  if c == 'end' then c = #line + 1
  elseif c < 0  then c = #line + c + 1  end
  return l, bound(c, 1, #line + 1)
end

--- Get the [$l, c] with the +/- offset applied
M.offset=function(t, off, l, c) --> l, c
  local len, m, llen, line = #t
  -- 0 based index for column
  l = bound(l, 1, len); c = bound(c - 1, 0, #get(t,l))
  while off > 0 do
    line = get(t, l)
    if nil == line then return len, #get(t,len) + 1 end
    llen = #line + 1 -- +1 is for the newline
    c = bound(c, 0, llen); m = llen - c
    if m > off then c = c + off; off = 0;
    else l, c, off = l + 1, 0, off - m
    end
    if l > len then return len, #get(t,len) + 1 end
  end
  while off < 0 do
    line = get(t,l)
    if nil == line then return 1, 1 end
    llen = #line
    c = bound(c, 0, llen); m = -c - 1
    if m < off then c = c + off; off = 0
    else l, c, off = l - 1, M.CMAX, off - m
    end
    if l <= 0 then return 1, 1 end
  end
  l = bound(l, 1, len)
  return l, bound(c, 0, #get(t,l)) + 1
end

--- get the byte offset 
M.offsetOf=function(t, l, c, l2, c2) --> int
  local off, len, llen = 0, #t
  l, c = M.bound(t, l, c, len);  l2, c2 = M.bound(t, l2, c2, len)
  c, c2 = c - 1, c2 - 1 -- column math is 0-indexed
  while l < l2 do
    llen = #get(t,l) + 1
    c = bound(c, 0, llen)
    off = off + (llen - c)
    l, c = l + 1, 0
  end
  while l > l2 do
    llen = #get(t,l) + ((l==len and 0) or 1)
    c = bound(c, 0, llen)
    off = off - c
    l, c = l - 1, M.CMAX
  end
  llen = #get(t,l) + ((l==len and 0) or 1)
  c, c2 = bound(c, 0, llen), bound(c2, 0, llen)
  off = off + (c2 - c)
  return off
end

--- find the pattern starting at l/c
--- Note: matches are only within a single line.
M.find = function(t, pat, l, c) --> (l, c, c2)
  l, c = M.bound(t, l or 1, c or 1)
  local c2
  while true do
    local s = get(t,l)
    if not s then return nil end
    c,c2 = s:find(pat, c); if c then return l, c,c2 end
    l, c = l + 1, 1
  end
end

local findBack = function(s, pat, end_)
  local s, fs, fe = s:sub(1, end_), nil, 0
  assert(#s < 256)
  while true do
    local _fs, _fe = s:find(pat, fe + 1)
    if not _fs then break end
    fs, fe = _fs, _fe
  end
  if fe == 0 then fe = nil end
  return fs, fe
end

--- find the pattern (backwards) starting at l/c
M.findBack = function(t, pat, l, c)
  l, c = M.bound(t, l or 1, c)
  local c2
  while true do
    local s = get(t,l)
    if not s then return nil end
    c,c2 = findBack(s, pat, c)
    if c then return l, c,c2 end
    l, c = l - 1, nil
  end
end

--- remove span (l, c) -> (l2, c2), return what was removed
M.remove = function(t, ...) --> string|table
  local l, c, l2, c2 = span(...);
  local len = #t
  if l2 > len then l2, c2 = len, #get(t,len) + 1 end
  local rem, new = {}, {}
  if l > l2 then -- empty span
  elseif c then -- includes column info
    if l == l2 then -- same line
      if c <= c2 then
        if c2 <= #get(t,l) then -- no newline
          new[1] = get(t,l):sub(1, c-1)..get(t,l):sub(c2+1)
          rem[1] = get(t,l):sub(c, c2)
        else -- include newline in removal
          l2 = l2 + 1 -- inset removes additional line
          new[1]         = get(t,l):sub(1, c-1)..(get(t,l2) or '')
          rem[1], rem[2] = get(t,l):sub(c, c2), ''
        end
      end
    else -- spans multiple lines
      local l1 = l
      if c <= #get(t,l) then new[1] = get(t,l):sub(1, c - 1)
      else l1 = l+1;     new[1] = get(t,l)..(get(t,l1) or '') end
      rem[1] = get(t,l):sub(c)
      for i=l1+1,l2-1 do push(rem, get(t,i)) end
      if l1 < l2 then
        if c2 > #get(t,l2) then push(rem, get(t,l2)) -- include newline
        else
          push(rem, get(t,l2):sub(1, c2)); push(new, get(t,l2):sub(c2 + 1))
        end
      end
    end
  else -- only lines, no col info
    for i=l,l2 do push(rem, get(t,i)) end
  end
  ds.inset(t, l, new, l2 - l + 1)
  return rem
end

-- return the box bounded top-left(l1,c1) and bot-right(l2,c2)
M.box = function(t, l1, c1, l2, c2, fill) --> lines
  local f = fill and assert(type(fill) == 'string') and (c2 - c1 + 1)
  local b = {}; for l=l1,l2 do
    local line = get(t,l)
    line = line and line:sub(c1, c2) or ''
    if fill and #line < f then line = line..srep(fill, f - #line) end
    push(b, line)
  end
  return b
end

-------------------------
-- Save / Load from file

--- load lines from file or path. On error return (nil, errstr)
M.load = function(f, close) --> (table?, errstr?)
  local err
  if type(f) == 'string' then close, f, err = true, io.open(f, 'r') end
  if f == nil then return nil, err or 'load(f=nil)' end
  local i, t = 1, {}
  for line in f:lines() do set(t,i, line); i = i + 1 end
  if close then f:close() end
  return t
end

--- write lines [$t] to file [$f] in chunks (default = 16KiB)
--- if f is a string then it is opened as a file and closed when done
M.dump = function(t, f, close, chunk)
  if type(f) == 'string' then
    f = assert(io.open(f, 'w')); close = true
  end
  if #t == 0 then
    if close then f:close() end
    return
  end
  local dat, len, chunk = {}, 0, chunk or M.CHUNK
  for i=1,#t-1 do; local line = t[i]
    push(dat, line); len = len + #line + 1
    if len >= chunk then
      push(dat, '\n')
      assert(f:write(concat(dat, '\n')))
      ds.clear(dat)
      len = 0
    end
  end
  push(dat, t[#t])
  assert(f:write(concat(dat, '\n')))
  if close then f:close() end
end

--- Logic to make a table behave like a [$file:write(...)] method.
---
--- This is NOT performant, especially for large lines.
M.write = function(t, ...) --> true
  local w = args(...); if #w == 0 then return true end
  local len, first = #t, w[1]
  if first ~= '' then
    if len == 0 then set(t,1, first)
    else             set(t,len, get(t,len)..first) end
  end
  for i=2,#w do set(t, len + i - 1, w[i]) end
  return true
end

return M
