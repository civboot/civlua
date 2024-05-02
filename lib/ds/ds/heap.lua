local mty = require'metaty'
local ds  = require'ds'
local bt = ds.bt
local push = table.insert

local M = mty.docTy({}, 'Binary Heap implementation')

-- Get the index which compares true of all: n, left(n), right(n)
local function cmpi(h, li, hi, n, cmp)
  local lefti = bt.lefti(h, n)
  if lefti > hi then return n end -- node has no children
  local i, righti = n, bt.righti(h, n)
  if cmp(h[lefti],  h[i]) then i = lefti  end
  if righti <= hi and cmp(h[righti], h[i]) then
    i = righti
  end
  return i
end

-- percolate n (node index) down the tree (left -> right)
-- n starts at a high index (start of heap) and we fix it.
local function percDown(h, li, hi, n, cmp)
  local i = cmpi(h, li, hi, n, cmp)
  while i ~= n do
    h[n], h[i] = h[i], h[n] -- swap, parent is largest
    -- keep following the path of i
    n, i = i, cmpi(h, li, hi, i, cmp)
  end
end

-- percolate n (node index) up
-- n starts at a high index (end of heap) and we fix it.
local function percUp(h, li, hi, n, cmp)
  local p = bt.parenti(h, n)
  while p >= li do
    local i = cmpi(h, li, hi, p, cmp)
    if i == p then break end -- parent is correct
    h[p], h[i] = h[i], h[p]
    -- keep following parent up
    n, p = p, bt.parenti(h, p)
  end
end

-- Initialize heap from unstructured table h
local function init(h, cmp)
  local li, hi = 1, #h
  if hi - li <= 0 then return end -- length 1 or 0
  local n = bt.parenti(h, hi) -- parent of right-most node
  while n >= li do -- keep fixing nodes until it is a heap
    percDown(h, li, hi, n, cmp)
    n = n - 1
  end
end

M.Heap = mty.doc[[
Heap(t, cmp) binary heap using a table.
A binary heap is a binary tree where the value of the parent always
satisfies `cmp(parent, child) == true`
  Min Heap: cmp = function(p, c) return p < c end (default)
  Max Heap: cmp = function(p, c) return p > c end

add and push take only O(log n), making it very useful for
priority queues and similar problems.
]](mty.record2'Heap') {
  'cmp[function]: comparison function to use'
}
getmetatable(M.Heap).__call = function(T, t, cmp)
  t.cmp = cmp or ds.lt
  init(t, t.cmp)
  return mty.construct(T, t)
end

M.Heap.add = mty.doc[[h:add(v) add value to the heap.]]
(function(h, v) push(h, v); percUp(h, 1, #h, #h, h.cmp) end)

M.Heap.pop = mty.doc[[h:pop() -> v: pop the top node.]]
(function(h)
  if #h <= 1 then return table.remove(h) end
  -- move last child to root and fix
  local v = h[1]; h[1] = table.remove(h)
  percDown(h, 1, #h, 1, h.cmp)
  return v
end)

return M
