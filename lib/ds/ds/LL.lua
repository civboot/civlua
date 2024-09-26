local mty = require'metaty'
--- Doubly Linked List with DSL operators.
---
--- Examples: the below examples use [+
---   * h as the "head", hN is N nodes to it's right (h1=h.r)
---   * t as the "tail", hN is N nodes to it's left  (t1=t.l)
---   * u indicates "unused" and is necessary for lua's syntax
--- ]
---
--- '+' is "add value" operator, it returns the added node [{## lang=lua}
---   t = LL(3) + 4 -- (  3 -> t=4)
---   h = t:head()  -- (h=3 -> t=4)
--- ]#
---
--- '-' is "link nodes" operator, it puts the nodes on the right
--- and returns the first node [{## lang=lua}
---   u = t - (LL(5) + 6) -- (h=3 -> t=4 -> 5 -> 6)
---   t = t:tail()        -- (h=3 -> 4   -> 5 -> t=6)
---   h1 = h.r - LL(3.1)  -- (h=3 -> h1=3.1 -> 4 -> 5 -> t=6)
--- ]##
---
--- ':extend' puts a list of values as nodes at onto tail [{## lang=lua}
---   h = (LL(3) + 4 + 5):head() -- (h=3 -> 4 -> 5)
---   h:extend{6, 7, 8}          -- (h=3 -> 4 -> 5 -> 6 -> 7 -> 8)
--- ]##
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

LL.head = function(ll) while ll.l do ll = ll.l end; return ll end
LL.tail = function(ll) while ll.r do ll = ll.r end; return ll end

LL.tolist = function(ll) --> {a.v, b.v, c.v, ...}
  local t = {}; while ll do push(t, ll.v); ll = ll.r end
  return t
end

--- create l -> r link
LL.link = function(l, r) l.r, r.l = r, l end

--- insert LL(v) to right of ll
--- [$(h -> 2); h:insert(1) ==> (h -> 1 -> 2)]
LL.insert = function(ll, v)
  ll.r = construct(getmetatable(ll), {v=v, l=ll, r=ll.r})
end

--- remove node ll from linked list
--- if ll was the head, returns the new head (or nil)
LL.rm = function(ll) --> head?
  local l, r = ll.l, ll.r
  if l then
    if r then l.r, r.l, ll.l, ll.r = r, l -- both left+right
    else        ll.l, l.r = nil end       -- only left
  elseif r then -- only right
    ll.r, r.l = nil
    return r -- new head
  end
end

LL.get = function(ll, i) --> node? (at index +/- i)
  if i < 0 then
    for i=1,-i do
      ll = ll.l; if not ll then return end
    end
  else
    for i=1,i do
      ll = ll.r; if not ll then return end
    end
  end
  return ll
end


--- Add DSL (ll + v). Puts node with v=v after tail, returns new tail.
LL.__add = function(ll, v) --> tail
  local n = getmetatable(ll)(v)
  ll:tail():link(n)
  return n
end

--- Link DSL: l - r ==> l -> r
--- Links [$l:tail() -> r:head(), return r:tail()]
---
--- Note: This is for convienience and expressiveness of small lists.
---       Use link() or insert() if performance matters.
---
--- Example: [{## lang=lua}
---   l6     = LL(3) - (LL(4) + 5) - L(6) ==> (3 -> 4 -> 5 -> 6)
---   l3tail = l1 - l2 - l3
--- ]##
LL.__sub = function(l, r)
  local t = r:tail()
  l, r = l:tail(), r:head()
  l.r, r.l = r, l -- link
  return t
end

LL.__call = function(ll) return ll.r end --> ll.r (use with `for`)
LL.__pairs  = ds.nosupport
LL.__ipairs = ds.nosupport
LL.__fmt = function(ll, fmt)
  push(fmt, 'LL{')
  while true do
    fmt(ll.v); ll = ll.r
    if ll then push(fmt, ' -> ') else break end
  end
  push(fmt, '}')
end

return LL
