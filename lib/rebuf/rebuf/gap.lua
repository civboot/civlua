-- line-based gap buffer.
--
-- The buffer is composed of two lists (stacks)
-- of lines.
--
-- 1. The "bot" (aka bottom) contains line 1 -> curLine.
--    curLine is at #bot. Data gets added to bot.
-- 2. The "top" buffer is used to store data in lines
--    after "bot" (aka after curLine). If the cursor is
--    moved to a previous line then data is moved from top to bot

local pkg = require'pkg'
local mty = pkg'metaty'
local ds  = pkg'ds'

local add, pop, concat = table.insert, table.remove, table.concat
local sub = string.sub

local M = {} -- module

---------------------------
-- Utilities
-- I should seriously consider moving all of these

local max, min, bound = ds.max, ds.min, ds.bound
local copy, drain = ds.copy, ds.drain

-- return the first i characters and the remainder
M.strdivide = function(s, i)
  return string.sub(s, 1, i), string.sub(s, i+1)
end
M.strinsert = function (s, i, v)
  return string.sub(s, 1, i-1) .. v .. string.sub(s, i)
end

-- Get line+column information
local function lcs(l, c, l2, c2)
  if nil == l2 and nil == c2 then return l, nil, c, nil end
  if nil == l2 or  nil == c2 then error(
    'must provide 2 or 4 indexes (l, l2) or (l, c, l2, c2'
  )end;
  return l, c, l2, c2
end; M.lcs = lcs

-- get the left/top most location of lcs
M.lcsLeftTop = function(...)
  local l, c, l2, c2 = lcs(...)
  c, c2 = c or 1, c2 or 1
  if l == l2 then return l, min(c, c2) end
  if l < l2  then return l, c end
  return l2, c2
end

local Gap = mty.record('Gap')
  :field('bot', 'table')
  :field('top', 'table')

Gap.CMAX = 999
M.Gap = Gap

Gap.__fmt = function(g, f)
  local len = #g
  for i, l in ipairs(g.bot) do
    add(f, l);
    if i < len then add(f, '\n') end
  end
  for i=#g.top,1,-1 do
    add(f, g.top[i]);
    if i > 1 then add(f, '\n') end
  end
end

Gap.new = function(s)
  s = s or {''}
  if type(s) == 'string' then s = ds.lines(s) end
  return Gap{ bot=s, top={} }
end

Gap.__len = function(g) return #g.bot + #g.top end

Gap.cur = function(g) return g.bot[#g.bot]  end

Gap.get = function(g, l)
  local bl = #(g.bot)
  if l <= bl then return g.bot[l]
  else return g.top[#g.top - (l - bl) + 1] end
end

local gapIndex = Gap.__index
Gap.__index = function(g, k)
  if type(k) == 'number' then return Gap.get(g, k) end
  return gapIndex(g, k)
end

local function ipairsGap(g, i)
  i = i + 1; if i > Gap.__len(g) then return end
  return i, Gap.get(g, i)
end
Gap.__ipairs = function(g) return ipairsGap, g, 0 end
Gap.__pairs  = Gap.__ipairs

Gap.last=function(g) return g:get(#g) end
Gap.bound=function(g, l, c, len, line)
  len = len or Gap.__len(g)
  l = bound(l, 1, len)
  if not c then return l end
  return l, bound(c, 1, #(line or g:get(l)) + 1)
end

-- Get the l, c with the +/- offset applied
Gap.offset=function(g, off, l, c)
  local len, m, llen, line = Gap.__len(g)
  -- 0 based index for column
  l = bound(l, 1, len); c = bound(c - 1, 0, #g:get(l))
  while off > 0 do
    line = g:get(l)
    if nil == line then return len, #g[len] + 1 end
    llen = #line + 1 -- +1 is for the newline
    c = bound(c, 0, llen); m = llen - c
    if m > off then c = c + off; off = 0;
    else l, c, off = l + 1, 0, off - m
    end
    if l > len then return len, #g:get(len) + 1 end
  end
  while off < 0 do
    line = g:get(l)
    if nil == line then return 1, 1 end
    llen = #line
    c = bound(c, 0, llen); m = -c - 1
    if m < off then c = c + off; off = 0
    else l, c, off = l - 1, Gap.CMAX, off - m
    end
    if l <= 0 then return 1, 1 end
  end
  l = bound(l, 1, len)
  return l, bound(c, 0, #g:get(l)) + 1
end

Gap.offsetOf=function(g, l, c, l2, c2)
  local off, len, llen = 0, Gap.__len(g)
  l, c = g:bound(l, c, len);  l2, c2 = g:bound(l2, c2, len)
  c, c2 = c - 1, c2 - 1 -- column math is 0-indexed
  while l < l2 do
    llen = #g:get(l) + 1
    c = bound(c, 0, llen)
    off = off + (llen - c)
    l, c = l + 1, 0
  end
  while l > l2 do
    llen = #g:get(l) + ((l==len and 0) or 1)
    c = bound(c, 0, llen)
    off = off - c
    l, c = l - 1, Gap.CMAX
  end
  llen = #g:get(l) + ((l==len and 0) or 1)
  c, c2 = bound(c, 0, llen), bound(c2, 0, llen)
  off = off + (c2 - c)
  return off
end

-- set the gap to the line
Gap.setGap = function(g, l)
  l = l or (#g.bot + #g.top)
  assert(l > 0)
  if l == #g.bot then return end -- do nothing
  if l < #g.bot then
    while l < #g.bot do
      local v = pop(g.bot)
      if nil == v then break end
      add(g.top, v)
    end
  else -- l > #g.bot
    while l > #g.bot do
      local v = pop(g.top)
      if nil == v then break end
      add(g.bot, v)
    end
  end
end

-- get the sub-buf (slice)
-- of lines (l, l2) or str (l, c, l2, c2)
Gap.sub=function(g, ...)
  local l, c, l2, c2 = lcs(...)
  local len = Gap.__len(g)
  local lb, lb2 = bound(l, 1, len), bound(l2, 1, len+1)
  if lb  > l  then c = 1 end
  if lb2 < l2 then c2 = nil end -- EoL
  l, l2 = lb, lb2
  local s = {} -- s is sub
  for i=l, min(l2,          #g.bot) do add(s, g.bot[i]) end
  for i=1, min((l2-l+1)-#s, #g.top) do add(s, g.top[#g.top - i + 1]) end
  if nil == c then -- skip, only lines
  elseif #s == 0 then s = '' -- empty
  elseif l == l2 then
    assert(1 == #s); local line = s[1]
     s = sub(line, c, c2)
    if c2 > #line and l2 < len then s = s..'\n' end
  else
    local last = s[#s];
    s[1] = sub(s[1], c); s[#s] = sub(last, 1, c2)
    if c2 > #last and l2 < len then add(s, '') end
    s = table.concat(s, '\n')
  end
  return s
end

-- find the pattern starting at l/c
Gap.find=function(g, pat, l, c)
  c = c or 1
  while true do
    local s = g:get(l)
    if not s then return nil end
    c = s:find(pat, c); if c then return l, c end
    l, c = l + 1, 1
  end
end

-- TODO: get from motion
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

-- find the pattern (backwards) starting at l/c
Gap.findBack = function(g, pat, l, c)
  while true do
    local s = g:get(l)
    if not s then return nil end
    c = findBack(s, pat, c)
    if c then return l, c end
    l, c = l - 1, nil
  end
end

--------------------------
-- Gap Mutations

-- insert s (string) at l, c
Gap.insert=function(g, s, l, c)
  g:setGap(l)
  local cur = pop(g.bot)
  g:extend(M.strinsert(cur, c or 1, s))
end

-- remove from (l, c) -> (l2, c2), return what was removed
Gap.remove=function(g, ...)
  local l, c, l2, c2 = lcs(...);
  local len = Gap.__len(g)
  if l2 > len then l2, c2 = len, Gap.CMAX end
  g:setGap(l2)
  if l2 < l then
    if nil == c then return {}
    else             return '' end
  end
  -- b=begin, e=end (of leftover text)
  local b, e, out, rmNewline = '', '', drain(g.bot, l2 - l + 1)
  if c == nil then      -- only lines, leave as list
  else
    rmNewline = c2 > #(out[#out])
    if #out == 1 then -- no newlines
      b, out[1], e = sub(out[1], 1, c-1), sub(out[1], c, c2), sub(out[1], c2+1)
    else -- has new line
      b, out[1]    = M.strdivide(out[1], c-1)
      out[#out], e = M.strdivide(out[#out], c2)
    end
    local leftover = b .. e
    if rmNewline and #g.top > 0 then
      g.top[#g.top] = leftover .. g.top[#g.top]
      add(out, '')
    else add(g.bot, leftover) end
    out = concat(out, '\n')
  end
  if 0 == #g.bot then
    if 0 == #g.top then add(g.bot, '')
    else  add(g.bot, pop(g.top)) end
  end
  return out
end

Gap.append=function(g, s)
  g:setGap(); add(g.bot, s)
end

-- extend onto gap
Gap.extend=function(g, s)
  if type(s) == 'string' then s = ds.lines(s) end
  for _, l in ipairs(s) do add(g.bot, l) end
end

Gap.getLine = Gap.get

return M
