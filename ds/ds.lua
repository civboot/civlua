local mty = require 'metaty'
local record, Any = mty.record, mty.Any
local add = table.insert

local M = {
  steal = mty.steal, trimWs = mty.trimWs,
}

---------------------
-- Order checking functions
M.isWithin = function(v, min, max)
  local out = (min <= v) and (v <= max)
  return out
end
M.min = function(a, b) return (a<b) and a or b end
M.max = function(a, b) return (a>b) and a or b end
M.bound = function(v, min, max)
  return ((v>max) and max) or ((v<min) and min) or v
end
M.sort2 = function(a, b)
  if a <= b then return a, b end; return b, a
end

---------------------
-- Number Functions
M.isEven = function(a) return a % 2 == 0 end
M.isOdd  = function(a) return a % 2 == 1 end
M.decAbs = function(v)
  if v == 0 then return 0 end
  return ((v > 0) and v - 1) or v + 1
end

---------------------
-- String Functions

--- return the first i characters and the remainder
M.strDivide = function(s, i)
  return string.sub(s, 1, i), string.sub(s, i+1)
end

-- insert the value string at index
M.strInsert = function (s, i, v)
  return string.sub(s, 1, i-1) .. v .. string.sub(s, i)
end

M.matches = function(s, m)
  local out = {}; for v in string.gmatch(s, m) do
    add(out, v) end
  return out
end

-- work with whitespace in strings
M.explode = function(s) return M.matches(s, '.') end
M.splitWs = function(s) return M.matches(s, "[^%s]+") end
M.concatToStrs = function(t, sep)
  local o = {}; for _, v in ipairs(t) do add(o, tostring(v)) end
  return table.concat(o, sep)
end

M.diffCol = function(sL, sR)
  local i, sL, sR = 1, M.explode(sL), M.explode(sR)
  while i <= #sL and i <= #sR do
    if sL[i] ~= sR[i] then return i end
    i = i + 1
  end
  if #sL < #sR then return #sL + 1 end
  if #sR < #sL then return #sR + 1 end
  return nil
end

---------------------
-- lines module

-- Address lines span via either (l,l2) or (l,c, l2,c2)
local function span(l, c, l2, c2)
  if not (l2 or c2) then return l, nil, c, nil end --(l,   l2)
  if      l2 and c2 then return l, c, l2, c2   end --(l,c, l2,c2)
  error'span must be 2 or 4 indexes: (l, l2) or (l, c, l2, c2)'
end

M.lines = {span=span}
function M.lines.split(s) return M.matches(s, '[^\n]*') end
function M.lines.sub(t, ...)
  local l, c, l2, c2 = span(...)
  local len = #t
  local lb, lb2 = M.bound(l, 1, len), M.bound(l2, 1, len+1)
  if lb  > l  then c = 1 end
  if lb2 < l2 then c2 = nil end -- EoL
  l, l2 = lb, lb2
  local s = {} -- s is sub
  for i=l,l2 do add(s, t[i]) end
  if    nil == c then -- skip, only lines
  elseif #s == 0 then s = '' -- empty
  elseif l == l2 then
    assert(1 == #s); local line = s[1]
     s = string.sub(line, c, c2)
    if c2 > #line and l2 < len then s = s..'\n' end
  else
    local last = s[#s]
    s[1] = string.sub(s[1], c); s[#s] = string.sub(last, 1, c2)
    if c2 > #last and l2 < len then add(s, '') end
    s = table.concat(s, '\n')
  end
  return s
end

function M.lines.diff(linesL, linesR)
  local i = 1
  while i <= #linesL and i <= #linesR do
    local lL, lR = linesL[i], linesR[i]
    if lL ~= lR then
      return i, assert(M.diffCol(lL, lR))
    end
    i = i + 1
  end
  if #linesL < #linesR then return #linesL + 1, 1 end
  if #linesR < #linesL then return #linesR + 1, 1 end
  return nil
end

--------------------
-- Working with file paths
M.path = {}
M.path.concat = mty.doc[[concat a table of path elements.
This preserves the first and last '/'.
a, b, c/d/e   -> a/b/c/d/e
/a/, /b, c/d/ -> /a/b/c/d/
]](function(t)
  if #t == 0 then return '' end
  local root = (t[1]:sub(1,1)=='/') and '/' or ''
  local dir  = (t[#t]:sub(-1)=='/') and '/' or ''
  local out = {}
  for i, p in ipairs(t) do
    p = string.match(p, '^/*(.-)/*$')
    if p ~= '' then add(out, p) end
  end; return root..table.concat(out, '/')..dir
end)

M.path.first = mty.doc[[split the path into (first, rest)]]
(function(path)
  if path:sub(1,1) == '/' then return '/', path:sub(2) end
  local a, b = path:match('^(.-)/(.*)$')
  if not a or a == '' or b == '' then return path, '' end
  return a, b
end)

M.path.last = mty.doc[[split the path into (start, last)]]
(function(path)
  local a, b = path:match('^(.*)/(.+)$')
  if not a or a == '' or b == '' then return '', path end
  return a, b
end)

---------------------
-- Table Functions

-- reverse a list-like table in-place
M.reverse = function(t)
  local l = #t;
  for i=1, l/2 do
    t[i], t[l-i+1] = t[l-i+1], t[i]
  end
  return t
end

M.extend = function(t, vals)
  for _, v in ipairs(vals) do add(t, v) end
end
M.update = function(t, add)
  for k, v in pairs(add) do t[k] = v end
end
M.updateKeys = function(t, add, keys)
  for _, k in ipairs(keys) do t[k] = add[k] end
end

-- pop multiple keys, pops(t, {'a', 'b'})
M.pops = function(t, keys)
  local o = {}
  for _, k in ipairs(keys) do o[k] = t[k]; t[k] = nil end
  return o
end

M.drain = function(t, len)
  local out = {}
  for i=1, M.min(#t, len) do add(out, table.remove(t)) end
  return M.reverse(out)
end

M.getOrSet = function(t, k, newFn)
  local v = t[k]; if v then return v end
  if newFn then v = newFn(t, k); t[k] = v end
  return v
end

-- assertEq(7, getPath({a={b=7}}, {'a', 'b'}))
M.getPath = function(d, path)
  for i, k in ipairs(path) do
    local nxt = d[k]
    if not nxt then return nil end
    d = nxt
  end
  return d
end

M.emptyTable = function() return {} end
M.setPath = function(d, path, value, newFn)
  local newFn = newFn or M.emptyTable
  local len = #path; assert(len > 0, 'empty path')
  for i, k in ipairs(path) do
    if i >= len then break end
    d = M.getOrSet(d, k, newFn)
  end
  d[path[len]] = value
end

M.indexOf = function(t, find)
  for i, v in ipairs(t) do
    if v == find then return i end
  end
end

function M.indexOfPat(strs, pat)
  for i, s in ipairs(strs) do if s:find(pat) then return i end end
end

---------------------
-- Untyped Functions
M.copy = function(t, update)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  setmetatable(out, getmetatable(t))
  if update then
    for k, v in pairs(update) do out[k] = v end
  end
  return out
end
M.deepcopy = function(t)
  local out = {}; for k, v in pairs(t) do
    if 'table' == type(v) then v = M.deepcopy(v) end
    out[k] = v
  end
  return setmetatable(out, getmetatable(t))
end

M.iter = function(l)
  local i = 0
  return function()
    i = i + 1; if i <= #l then return i, l[i] end
  end
end

M.iterV = function(l)
  local i = 0
  return function()
    i = i + 1; if i <= #l then return l[i] end
  end
end

---------------------
-- File Functions
function M.readPath(path)
  local f = mty.assertf(io.open(path), 'invalid %s', path)
  local out = f:read('a'); f:close()
  return out
end

function M.writePath(path, text)
  local f = mty.assertf(io.open(path, 'w'), 'invalid %s', path)
  local out = f:write(text); f:close()
  return out
end

M.fdMv = mty.doc[[fdMv(fdTo, fdFrom): memonic fdTo = fdFrom
Read data from fdFrom and write to fdTo, then flush.
]](function(fdTo, fdFrom)
  while true do
    local d = fdFrom:read(4096); if not d then break end
    fdTo:write(d)
  end fdTo:flush()
  return fdTo, fdFrom
end)

---------------------
-- Source Code Functions
M.callerSource = function()
  local info = debug.getinfo(3)
  return string.format('%s:%s', info.source, info.currentline)
end

M.eval = function(s, env, name) -- Note: not typed
  assert(type(s) == 'string'); assert(type(env) == 'table')
  name = name or M.callerSource()
  local e, err = load(s, name, 't', env)
  if err then return false, err end
  return pcall(e)
end

---------------------
-- none and bool
M.NONE = setmetatable({}, {
  __doc = [[none means "set as none" (nil means "unset")]],
  __name='none', __tostring=function() return 'none' end,
  __eq=rawequal, __metatable='none',
  __index=   function() error'get on "none"' end,
  __newindex=function() error'set on "none"' end,
})
_G.none = (_G.none==nil) and M.NONE or _G.none; M.none = _G.none
M.bool = mty.doc[[convert to boolean (none aware)]]
(function(v) return not rawequal(none, v) and v and true or false end)

---------------------
-- Duration
local NANO  = 1000000000
local function durationSub(s, ns, s2, ns2)
  s, ns = s - s2, ns - ns2
  if ns < 0 then
    ns = NANO + ns
    s = s - 1
  end
  return s, ns
end

local function assertTime(t)
  assert(math.floor(t.s) == t.s, 'non-int seconds')
  assert(math.floor(t.ns) == t.ns, 'non-int nano-seconds')
  assert(t.ns < NANO, 'ns too large')
  return t
end

local timeNew = function(ty_, s, ns)
  if ns == nil then return ty_:fromSeconds(s) end
  local out = {s=s, ns=ns}
  return setmetatable(assertTime(out), ty_)
end
local fromSeconds = function(ty_, s)
  local sec = math.floor(s)
  return ty_(sec, math.floor(NANO * (s - sec)))
end
local fromMs = function(ty_, s)     return ty_(s / 1000) end
local fromMicros = function(ty_, s) return ty_(s / 1000000) end
local asSeconds = function(time) return time.s + (time.ns / NANO) end

M.Duration = record('Duration', {__call=timeNew})
  :field('s', 'number') :field('ns', 'number')

M.Duration.NANO = NANO
M.Duration.fromSeconds = fromSeconds
M.Duration.fromMs = fromMs
M.Duration.asSeconds = asSeconds
M.Duration.__sub = function(self, r)
  assert(mty.ty(r) == M.Duration)
  local s, ns = durationSub(self.s, self.ns, r.s, r.ns)
  return M.Duration(s, ns)
end
M.Duration.__lt = function(self, o)
  if self.s < o.s then return true end
  return self.ns < o.ns
end
M.Duration.__fmt = nil
M.Duration.__tostring = function(self) return self:asSeconds() .. 's' end

---------------------
-- Epoch: time since the unix epoch. Interacts with duration.
M.Epoch = record('Epoch', {__call=timeNew})
  :field('s', 'number') :field('ns', 'number')

M.Epoch.fromSeconds = fromSeconds
M.Epoch.asSeconds = asSeconds
M.Epoch.__sub = function(self, r)
  assert(self);     assert(r)
  assertTime(self); assertTime(r)
  local s, ns = durationSub(self.s, self.ns, r.s, r.ns)
  if mty.ty(r) == M.Duration then return M.Epoch(s, ns) end
  assert(mty.ty(r) == M.Epoch, 'can only subtract Duration or Epoch')
  return M.Duration(s, ns)
end
M.Epoch.__fmt = nil
M.Epoch.__tostring = function(self)
  return string.format('Epoch(%ss)', self:asSeconds())
end

---------------------
-- Set
M.Set = mty.rawTy('Set', {
  __call=function(ty_, t)
    local s = {}
    for _, k in ipairs(t) do s[k] = true end
    return setmetatable(s, ty_)
  end,
})

-- Pretty much the same as tblFmt except don't print values
M.Set.__fmt = function(self, f)
  f:levelEnter('Set{')
  local keys = mty.orderedKeys(self, f.set.keysMax)
  for i, k in ipairs(keys) do
    f:fmt(k)
    if i < #keys then f:sep(f.set.itemSep) end
  end
  if #keys >= f.set.keysMax then add(f, '...'); end
  f:levelLeave('}')
end

M.Set.__eq = function(self, t)
  local len = 0
  for k in pairs(self) do
    if not t[k] then return false end
    len = len + 1
  end
  for _ in pairs(t) do -- ensure lengths are the same
    len = len - 1
    if len < 0 then return false end
  end
  return true
end

M.Set.union = function(self, s)
  local both = M.Set{}
  for k in pairs(self) do if s[k] then both[k] = true end end
  return both
end

-- items in self but not in s
M.Set.diff = function(self, s)
  local left = M.Set{}
  for k in pairs(self) do if not s[k] then left[k] = true end end
  return left
end

---------------------
-- Linked List

M.LL = record('LL')
  :fieldMaybe('front', 'table')
  :fieldMaybe('back', 'table')

M.LL.isEmpty = function(self)
  return nil == self.front and assert(nil == self.back)
end

M.LL.addFront = function(self, v)
  if nil == v then return end
  local a = {v=v, nxt=self.front, prv=nil}
  if self.front then self.front.prv = a end
  self.front = a
  if not self.back then self.back = self.front end
  return self
end

M.LL.addBack = function(self, v)
  if nil == v then return end
  local a = {v=v, nxt=nil, prv=self.back}
  if self.back then self.back.nxt = a end
  self.back = a
  if not self.front then self.front = self.back end
  return self
end

M.LL.popFront = function(self)
  local o = self.front; if o == nil then return end
  self.front = o.nxt; if self.front then self.front.prv = nil
                      else self.back = nil end
  return o.v
end

M.LL.popBack = function(self)
  local o = self.back; if o == nil then return end
  self.back = o.prv; if self.back then self.back.nxt = nil
                     else self.front = nil end
  return o.v
end

return M
