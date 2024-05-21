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
--
-- TODO: migrate most of these methods to ds.lines
local M = mod and mod'rebuf.gap' or {}

local mty = require'metaty'
local ds, lines  = require'ds', require'ds.lines'
local span = lines.span

local push, pop, concat = table.insert, table.remove, table.concat
local move              = table.move
local sub = string.sub
local max = math.max

---------------------------
-- Utilities
-- I should seriously consider moving all of these

local max, min, bound = ds.max, ds.min, ds.bound
local copy, drain = ds.copy, ds.drain

local Gap = mty'Gap' {
  'bot[table]', 'top[table]'
}

Gap.CMAX = 999
M.Gap = Gap

Gap.__fmt = function(g, f)
  local len = #g
  for i, l in ipairs(g.bot) do
    push(f, l);
    if i < len then push(f, '\n') end
  end
  for i=#g.top,1,-1 do
    push(f, g.top[i]);
    if i > 1 then push(f, '\n') end
  end
end

Gap.new = function(s)
  s = s or {''}
  if type(s) == 'string' then s = lines(s) end
  return Gap{ bot=s, top={} }
end

Gap.__len = function(g) return #g.bot + #g.top end

Gap.cur = function(g) return g.bot[#g.bot]  end

Gap.get = function(g, l)
  local bl = #(g.bot)
  if l <= bl then return g.bot[l]
  else return g.top[#g.top - (l - bl) + 1] end
end

getmetatable(Gap).__index = nil
Gap.__index = function(g, k)
  local mt = getmetatable(g)
  if type(k) == 'number' then return mt.get(g, k) end
  return mt[k]
end

local function ipairsGap(g, i)
  i = i + 1; if i > Gap.__len(g) then return end
  return i, Gap.get(g, i)
end
Gap.__ipairs = function(g) return ipairsGap, g, 0 end
Gap.__pairs  = Gap.__ipairs

-- set the gap to the line
Gap.setGap = function(g, l)
  l = l or (#g.bot + #g.top)
  assert(l >= 0)
  if l == #g.bot then return end -- do nothing
  if l < #g.bot then
    while l < #g.bot do
      local v = pop(g.bot)
      if nil == v then break end
      push(g.top, v)
    end
  else -- l > #g.bot
    while l > #g.bot do
      local v = pop(g.top)
      if nil == v then break end
      push(g.bot, v)
    end
  end
end

--------------------------
-- Gap Mutations

-- see ds.inset. Sets gap for better (real-world) performance than table of
-- lines.
Gap.__inset=function(g, i, values, rmlen)
  rmlen = rmlen or 0
  g:setGap(max(0, i + rmlen - 1))
  move(values, 1, math.max(#values, rmlen), i, g.bot)
  return g
end

-- remove span (l, c) -> (l2, c2), return what was removed
Gap.remove= lines.remove

Gap.append=function(g, s)
  g:setGap(); push(g.bot, s)
end

-- extend onto gap
Gap.extend=function(g, s)
  if type(s) == 'string' then s = lines(s) end
  for _, l in ipairs(s) do push(g.bot, l) end
end

Gap.getLine = Gap.get

return M
