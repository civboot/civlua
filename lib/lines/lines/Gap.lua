local mty = require'metaty'
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
-- Example:
--   Gap()
--   Gap'some\nlines'
--   Gap{bot={'some', 'lines'}}
local Gap = mty'Gap' { 'bot[table]', 'top[table]', 'path [string]' }

local ds, lines  = require'ds', require'lines'
local span = lines.span

local push, pop, concat = table.insert, table.remove, table.concat
local move              = table.move
local sub = string.sub
local max = math.max

getmetatable(Gap).__call = function(T, t)
  if type(t) == 'string' then t = {bot=lines(t), top={}}
  else
    t     = t     or {}
    t.bot = ds.popk(t, 'dat') or t.bot or {}
    t.top = t.top or {}
  end
  return mty.construct(T, t)
end

-- Load gap from file, which can be a path.
-- returns nil if f==nil or path DNE
Gap.load = function(T, f, close) --> Gap?
  local dat, err = lines.load(f, close)
  if not dat then return nil, err end
  return T{dat = dat, path=type(f) == 'string' and f or nil}
end

Gap.__len = function(g) return #g.bot + #g.top end
Gap.__index = function(g, l)
  if type(l) ~= 'number' then return getmetatable(g)[l] end
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

Gap.__newindex = function(g, i, v)
  assert(i == #g + 1, 'can only set at len+1')
  g:setGap(i); g.bot[i] = v
end

-- see lines.inset
-- This has much better performance than lines.inset when operations
-- are performed close together.
Gap.__inset = function(g, i, values, rmlen)
  rmlen = rmlen or 0
  g:setGap(max(0, i + rmlen - 1))
  move(values, 1, max(#values, rmlen), i, g.bot)
  return g
end

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

return Gap
