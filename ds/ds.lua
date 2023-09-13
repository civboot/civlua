local mty = require 'metaty'
local record, Fn, Any = mty.record, mty.Fn, mty.Any

local M = {}

---------------------
-- Any (orderable) Functions
local A2A = Fn{Any, Any}:out{Any}
local A3A = Fn{Any, Any, Any}:out{Any}
local A2B = Fn{Any, Any}:out{'boolean'}
local A3B = Fn{Any, Any, Any}:out{'boolean'}

M.isWithin = A3B:apply(function(v, min, max)
  local out = (min <= v) and (v <= max)
  print('! isWithin out', out)
  return out
end)

M.min = A2A:apply(function(a, b) return (a<b) and a or b end)
M.max = A2A:apply(function(a, b) return (a>b) and a or b end)
M.bound = A3A:apply(function(v, min, max)
  return ((v>max) and max) or ((v<min) and min) or v
end)
M.sort2 = Fn{Any, Any}:out{Any, Any}
:apply(function(a, b)
  if a <= b then return a, b end; return b, a
end)

---------------------
-- Number Functions
local N1B = Fn{'number'}:out{'boolean'}
local N1N = Fn{'number'}:out{'number'}
M.isEven = N1B:apply(function(a) return a % 2 == 0 end)
M.isOdd  = N1B:apply(function(a) return a % 2 == 1 end)
M.decAbs = N1N:apply(function(v)
  if v == 0 then return 0 end
  return ((v > 0) and v - 1) or v + 1
end)

---------------------
-- String Functions
local T1S = Fn{'table'}:out{'string'}

M.strLast = Fn{'string'}:out{'string'}
:apply(function(s) return s:sub(#s, #s) end)

--- return the first i characters and the remainder
M.strDivide = Fn{'string', 'number'}:out{'string', 'string'}
:apply(function(s, i)
  return string.sub(s, 1, i), string.sub(s, i+1)
end)

-- insert the value string at index
M.strInsert = Fn{'string', 'number', 'string'}:out{'string'}
:apply(function (s, i, v)
  return string.sub(s, 1, i-1) .. v .. string.sub(s, i)
end)

---------------------
-- Table Functions
local T1T = Fn{'table'}:out{'table'}
local T2V = Fn{'table', 'table'}

-- reverse a list-like table in-place
M.reverse = T1T:apply(function(t)
  local l = #t;
  for i=1, l/2 do
    t[i], t[l-i+1] = t[l-i+1], t[i]
  end
  return t
end)

M.extend = T2V:apply(function(t, vals)
  for _, v in ipairs(vals) do table.insert(t, v) end
end)
M.update = T2V:apply(function(t, add)
  for k, v in pairs(add) do t[k] = v end
end)

M.pop = Fn{'table', Any}:out{Any}
:apply(function(t, k)
  local v = t[k]; t[k] = nil; return v
end)

M.drain = Fn{'table', 'number'}:out{'table'}
:apply(function(t, len)
  local out = {}
  for i=1, M.min(#t, len) do table.insert(out, table.remove(t)) end
  return M.reverse(out)
end)

M.getOrSet = Fn{'table', Any, Any}:out{Any}
:apply(function(t, k, new)
  local v = t[k]; if v then return v end
  if new then v = new(t, k); t[k] = v end
  return v
end)

-- assertEq(7, getPath({a={b=7}}, {'a', 'b'}))
M.getPath = Fn{'table', 'table'}:out{Any}:outMaybe{true}
:apply(function(d, path)
  for i, k in ipairs(path) do
    local nxt = d[k]
    if not nxt then return nil end
    d = nxt
  end
  return d
end)

M.setPath = Fn{'table', 'table', Any}
:apply(function(d, path, value)
  local len = #path
  assert(len > 0, 'empty path')
  for i, k in ipairs(path) do
    if i >= len then break end
    d = M.getOrSet(d, k, function() return {} end)
  end
  d[path[len]] = value
end)

M.indexOf = Fn{'table', Any}:out{'number'}:outMaybe{true}
:apply(function(t, find)
  for i, v in ipairs(t) do
    if v == find then return i end
  end
end)

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
    if 'table' == type(v) then v = deepcopy(v) end
    out[k] = v
  end
  return setmetatable(out, getmetatable(t))
end

---------------------
-- File Functions
local function readPath(path)
  local f = io.open(path, 'r')
  local out = f:read('a'); f:close()
  return out
end

local function writePath(path, text)
  local f = io.open(path, 'w')
  local out = f:write(text); f:close()
  return out
end

---------------------
-- Source Code Functions
M.callerSource = Fn{}:out{'string'}
:apply(function()
  local info = debug.getinfo(3)
  return string.format('%s:%s', info.source, info.currentline)
end)

M.eval = function(s, env, name) -- Note: not typed
  assert(type(s) == 'string'); assert(type(env) == 'table')
  name = name or M.callerSource()
  local e, err = load(s, name, 't', env)
  if err then return false, err end
  return pcall(e)
end

---------------------
-- Duration
local NANO  = 1000000000
local MILLI = 1000000000
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
  return ty_(sec, NANO * (s - sec))
end
local fromMs = function(ty_, s)
  return ty_(s / 1000)
end
local asSeconds = function(time)
  return time.s + (time.ns / NANO)
end

M.Duration = record('Duration', {__call=timeNew})
  :field('s', 'number') :field('ns', 'number')

M.Duration.NANO = NANO
M.Duration.fromSeconds = fromSeconds
M.Duration.fromMs = fromMs
M.Duration.asSeconds = asSeconds
M.Duration.__sub = function(self, r)
  assert(ty(r) == Duration)
  local s, ns = durationSub(self.s, self.ns, r.s, r.ns)
  return Duration(s, ns)
end
M.Duration.__lt = function(self, o)
  if self.s < o.s then return true end
  return self.ns < o.ns
end
M.Duration.__tostring = function(self)
  return self:asSeconds() .. 's'
end

---------------------
-- Epoch: time since the unix epoch
M.Epoch = record('Epoch', {__call=timeNew})
  :field('s', 'number') :field('ns', 'number')

M.Epoch.fromSeconds = fromSeconds
M.Epoch.asSeconds = asSeconds
M.Epoch.__sub = function(self, r)
  assert(self);     assert(r)
  assertTime(self); assertTime(r)
  local s, ns = durationSub(self.s, self.ns, r.s, r.ns)
  if ty(r) == Duration then return Epoch(s, ns) end
  assert(ty(r) == Epoch)
  return Duration(s, ns)
end
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

M.Set.union = Fn{M.Set, Any}:out{M.Set} :apply(
function(self, s)
  local both = Set{}
  for k in pairs(self) do if s[k] then both[k] = true end end
  return both
end)

-- items in self but not in s
M.Set.diff = Fn{M.Set, Any}:out{M.Set}
:apply(function(self, s)
  local left = Set{}
  for k in pairs(self) do if not s[k] then left[k] = true end end
  return left
end)

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
