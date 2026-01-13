local mty = require'metaty'
--- line-based gap buffer. The buffer is composed of two lists (stacks) of
--- lines [+
--- 1. The "bot" (aka bottom) contains line 1 -> curLine.
---    curLine is at #bot. Data gets added to bot.
--- 2. The "top" buffer is used to store data in lines
---    after "bot" (aka after curLine). If the cursor is
---    moved to a previous line then data is moved from top to bot
--- ]
local Gap = mty'Gap' {
  'bot[table]', 'top[table]',
  'path [string]', 'readonly [bool]' }

local ds, lines  = require'ds', require'lines'
local pth = require'ds.path'
local lload = lines.load
local largs = lines._args
local span = lines.span

local push, pop, concat = table.insert, table.remove, table.concat
local move              = table.move
local sub = string.sub
local max = math.max
local getmt = getmetatable

local EMPTY = {}

getmetatable(Gap).__call = function(T, t, path)
  return mty.construct(T, {
    bot=(type(t) == 'string') and lines(t) or t or {},
    top={}, path=path
  })
end

Gap.flush = ds.noop
Gap.close = ds.noop
Gap.icopy = function(g) --> list
  local b = g.bot
  local o = move(b, 1, #b, 1, {})
  local t = g.top
  for i=#t, 1, -1 do push(o, t[i]) end
  return o
end

--- Load gap from file, which can be a path.
--- returns nil, err on error
Gap.load = function(T, f, close) --> Gap?, err?
  if type(f) == 'string' then f = pth.abs(f) end
  local dat, err = lload(f, close)
  if not dat then return nil, err end
  return T(dat, type(f) == 'string' and f or nil)
end

Gap.__len = function(g) return #g.bot + #g.top end
Gap.get = function(g, l)
  local bl = #g.bot
  if l <= bl then return g.bot[l]
  else            return g.top[#g.top - (l - bl) + 1] end
end
Gap.__index = function(g, l)
  if type(l) ~= 'number' then return getmetatable(g)[l] end
  return g:get(l)
end

Gap.__fmt = function(g, f)
  local len = #g
  for i, l in ipairs(g.bot) do
    f:write(l); if i < len then f:write'\n' end
  end
  for i=#g.top,1,-1 do
    f:write(g.top[i]); if i > 1 then f:write'\n' end
  end
end
Gap.__pairs = ipairs

--------------------------
-- Mutations

Gap.set = function(g, i, v)
  assert(not g.readonly, 'attempt to write to readonly Gap')
  assert(i <= #g + 1, 'can only set at len+1')
  g:setGap(i); g.bot[i] = v
end
Gap.__newindex = Gap.set

--- See ds.inset for documentation.
Gap.inset = function(g, i, values, rmlen) --> rm?
  assert(not g.readonly, 'attempt to write to readonly Gap')
  values, rmlen = values or EMPTY, rmlen or 0
  g:setGap(max(0, i + rmlen - 1))
  move(values, 1, max(#values, rmlen), i, g.bot)
end

Gap.extend = function(g, l)
  assert(not g.readonly, 'attempt to write to readonly Gap')
  g:setGap(#g); local bot = g.bot
  move(l, 1, #l, #bot + 1, bot)
  return g
end

--- set the gap to the line number, making [$l == #g.bot].
Gap.setGap = function(g, l)
  local bot, top = g.bot, g.top
  local blen = #bot
  l = l or (blen + #g.top)
  assert(l >= 0)
  if l == blen then return end -- do nothing
  if l < blen then
    while l < #bot do
      local v = pop(bot); if nil == v then break end
      push(top, v)
    end
  else -- l > #g.bot
    while l > #bot do
      local v = pop(top); if nil == v then break end
      push(bot, v)
    end
  end
end

Gap.write = function(g, ...)
  assert(not g.readonly, 'attempt to write to readonly Gap')
  local t = largs(...)
  local len = #t; if len == 0 then return end
  g:setGap()
  local bot = g.bot; local blen = #bot
  if blen == 0 then bot[1] = t[1]
  else              bot[blen] = bot[blen]..t[1] end
  for i=2, #t do push(bot, t[i]) end
end

Gap.dumpf = lines.dump

return Gap
