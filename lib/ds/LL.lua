local mty = require'metaty'
--- Doubly Linked List with DSL operators.
---
--- Examples: the below examples use [+
---   * h as the "head", hN is N nodes to it's right (h1=h.r)
---   * t as the "tail", hN is N nodes to it's left  (t1=t.l)
---   * u indicates "unused" and is necessary for lua's syntax
--- ]
---
--- '+' is "add value" operator, it returns the added node [{$$ lang=lua}
---   t = LL(3) + 4 -- (  3 -> t=4)
---   h = t:head()  -- (h=3 -> t=4)
--- ]#
---
--- '-' is "link nodes" operator, it puts the nodes on the right
--- and returns the first node [{$$ lang=lua}
---   u = t - (LL(5) + 6) -- (h=3 -> t=4 -> 5 -> 6)
---   t = t:tail()        -- (h=3 -> 4   -> 5 -> t=6)
---   h1 = h.r - LL(3.1)  -- (h=3 -> h1=3.1 -> 4 -> 5 -> t=6)
--- ]$
---
--- ':extend' puts a list of values as nodes at onto tail [{$$ lang=lua}
---   h = (LL(3) + 4 + 5):head() -- (h=3 -> 4 -> 5)
---   h:extend{6, 7, 8}          -- (h=3 -> 4 -> 5 -> 6 -> 7 -> 8)
--- ]$
local LL = mty'LL' {
  'l [&LL]: left node', 'r [&LL]: right node', 'v [any]: value',
}

local ds = require'ds'
local construct = mty.construct
local push = table.insert

getmetatable(LL).__call = function(T, v) return construct(T, {v=v}) end
LL.from = function(T, list) --> (head, tail) from list of vals
  local len = #list; if len == 0 then return end
  local h = LL(list[1]); local t = h
  for i=2,len do
    local n = LL(list[i]); t.r, n.l = n, t -- create new at end
    t = n -- new is now tail
  end
  return h, t
end

function LL:head() while self.l do self = self.l end; return self end
function LL:tail() while self.r do self = self.r end; return self end

function LL:tolist() --> {a.v, b.v, c.v, ...}
  local t = {}; while self do push(t, self.v); self = self.r end
  return t
end

--- create l -> r link
function LL:link(r) self.r, r.l = r, self end

--- insert LL(v) to right of ll
--- [$(h -> 2); h:insert(1) ==> (h -> 1 -> 2)]
function LL:insert(v)
  self.r = construct(getmetatable(self), {v=v, l=self, r=self.r})
end

--- remove node ll from linked list
--- if ll was the head, returns the new head (or nil)
function LL:rm() --> head?
  local l, r = self.l, self.r
  if l then
    if r then l.r, r.l, self.l, self.r = r, l -- both left+right
    else        self.l, l.r = nil end       -- only left
  elseif r then -- only right
    self.r, r.l = nil
    return r -- new head
  end
end

function LL:get(i) --> node? (at index +/- i)
  if i < 0 then
    for i=1,-i do
      self = self.l; if not self then return end
    end
  else
    for i=1,i do
      self = self.r; if not self then return end
    end
  end
  return self
end


--- Add DSL (self + v). Puts node with v=v after tail, returns new tail.
function LL:__add(v) --> tail
  local n = getmetatable(self)(v)
  self:tail():link(n)
  return n
end

--- Link DSL: [$l - r ==> l -> r]
--- Links [$l:tail() -> r:head(), return r:tail()]
---
--- Note: This is for convienience and expressiveness of small lists.
---       Use link() or insert() if performance matters.
---
--- Example: [{$$ lang=lua}
---   l6     = LL(3) - (LL(4) + 5) - L(6) ==> (3 -> 4 -> 5 -> 6)
---   l3tail = l1 - l2 - l3
--- ]$
function LL:__sub(r)
  local t = r:tail()
  local l, r = self:tail(), r:head()
  l.r, r.l = r, l -- link
  return t
end

function LL:__call() return self.r end --> self.r (use with `for`)
LL.__pairs  = ds.nosupport
LL.__ipairs = ds.nosupport
function LL:__fmt(f)
  f:write'LL{'
  while true do
    f(self.v); self = self.r
    if self then f:write' -> ' else break end
  end
  f:write'}'
end

return LL
