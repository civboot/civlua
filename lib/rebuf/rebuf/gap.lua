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

local max, min, bound = ds.max, ds.min, ds.bound
local copy, drain = ds.copy, ds.drain

local Gap = mty'Gap' { 'bot[table]', 'top[table]' }
M.Gap = Gap
getmetatable(Gap).__call = function(T, t)
  t = (type(t) == 'string') and lines(t) or t or {''}
  return mty.construct(T, { bot=t, top={} })
end

getmetatable(Gap).__index = nil
Gap.__len = function(g) return #g.bot + #g.top end
Gap.__index = function(g, l)
  if type(l) ~= 'number' then
    return assert(getmetatable(g)[l], 'invalid gap field')
  end
  local bl = #g.bot
  if l <= bl then return g.bot[l]
  else            return g.top[#g.top - (l - bl) + 1] end
end

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
Gap.__pairs = ipairs

--------------------------
-- Mutations

-- set the gap to the line
Gap.setGap = function(g, l)
  local bot, top = g.bot, g.top
  local blen = #bot
  l = l or (blen + #g.top)
  assert(l >= 0)
  if l == blen then return end -- do nothing
  if l < blen then
    while l < #bot do
      local v = pop(bot)
      if nil == v then break end
      push(top, v)
    end
  else -- l > #g.bot
    while l > #bot do
      local v = pop(top)
      if nil == v then break end
      push(bot, v)
    end
  end
end

-- see lines.inset
-- This has much better performance than lines.inset when operations
-- are performed close together.
Gap.__inset = function(g, i, values, rmlen)
  rmlen = rmlen or 0
  g:setGap(max(0, i + rmlen - 1))
  move(values, 1, math.max(#values, rmlen), i, g.bot)
  return g
end

Gap.__newindex = function(g, i, v)
  local len = #g
  assert(i == len + 1, 'cannot set above len+1')
  g:setGap(len); g.bot[len + 1] = v
end

return M
