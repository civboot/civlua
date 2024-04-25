local pkg = require'pkg'
local mty = pkg'metaty'
local record, Any = mty.record, mty.Any
local add, pop, sfmt = table.insert, table.remove, string.format

local M = {
  steal = mty.steal, trim = mty.trim,
}

M.SKIP     = 'skip'
M.noop     = function() end
M.retTrue  = function() return true  end
M.retFalse = function() return false end
M.newTable = function() return {}    end

M.coroutineErrorMessage = function(cor, err)
  return table.concat{
    'Coroutine error: ', debug.stacktraceback(cor, err), '\n',
    'Coroutine failed!',
  }
end

---------------------
-- Order checking functions
M.isWithin = function(v, min, max)
  local out = (min <= v) and (v <= max)
  return out
end
M.min = math.min -- TODO: remove these
M.max = math.max
M.lt  = function(a, b) return a < b end
M.gt  = function(a, b) return a > b end
M.lte = function(a, b) return a <= b end
M.bound = function(v, min, max)
  return ((v>max) and max) or ((v<min) and min) or v
end
M.sort2 = function(a, b)
  if a <= b then return a, b end; return b, a
end
M.repr = function(v) return sfmt('%q', v) end

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

-- split strings
M.split = mty.split
M.splitList = function(...)
  local t = {}; for _, v in mty.split(...) do add(t, v) end
  return t
end
M.explode = function(s) return M.matches(s, '.') end
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

M.q1str = function(s)
  return "'"..sfmt("%q", s):sub(2, -2)
    :gsub("'", "\\'"):gsub('\\"', '"').."'"
end

M.trimEnd = mty.doc[[trim the end of the string by removing pat (default='%s')]]
(function(subj, pat, index)
  pat = pat and ('^(.-)'..pat..'*$') or '^(.-)%s*$'
  return subj:match(pat, index)
end)

M.squash = mty.doc[[
Squash a string: convert all whitespace to repl (default=' ').
]](function(s, repl) return s:gsub('%s+', repl or ' ') end)

---------------------
-- lines module

-- Address lines span via either (l,l2) or (l,c, l2,c2)
local function span(l, c, l2, c2)
  if not (l2 or c2) then return l, nil, c, nil end --(l,   l2)
  if      l2 and c2 then return l, c, l2, c2   end --(l,c, l2,c2)
  error'span must be 2 or 4 indexes: (l, l2) or (l, c, l2, c2)'
end

M.lines = mty.doc[[
lines module, when called splits a string into lines.

lines(text) -> table of lines

Also has functions for working with a table of lines.

  lines.sub(myLines, l, c, l2, c2)
]](setmetatable({span=span}, {
  __call=function(_, text, index)
    local t = {}
    for _, line in mty.rawsplit, text, {'\n', index or 1} do
      add(t, line)
    end; return t
  end,
}))

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

M.lines.map = mty.doc[[create a table of lineText -> {lineNums}]]
(function(lines)
  local map = {}; for l, line in ipairs(lines) do
    add(M.getOrSet(map, line, M.emptyTable), l)
  end
  return map
end)

--------------------
-- Working with file paths
M.path = pkg.path
M.path.splitList = function(path) return M.splitList(path, '/+') end

---------------------
-- Table Functions
M.isEmpty = mty.doc'return whether a table is empty'
(function(t) return next(t) == nil end)

M.only = mty.doc'get the first and only element of the list'
(function(t)
  mty.assertf(#t == 1, 'len ~= 1: %s', #t)
  return t[1]
end)

M.values = mty.doc'get only the values of pairs(t) as a list'
(function(t)
  local vals = {}; for _, v in pairs(t) do add(vals, v) end
  return vals
end)

M.keys = mty.doc'get only the keys of pairs(t) as a list'
(function(t)
  local keys = {}; for k in pairs(t) do add(keys, k) end
  return keys
end)

M.inext = mty.doc'next(t, key) but with indexes'(ipairs{})

M.iprev = mty.doc'inext but reversed.'
(function(t, i) if i > 1 then return i - 1, t[i - 1] end end)

M.ireverse = mty.doc'ipairs reversed'
(function(t) return M.iprev, t, #t + 1 end)

M.rawislice = mty.doc'for i, v in rawislice({t, endi}, starti)'
(function(state, i)
  i = i + 1; if i > state[2] then return end
  return i, state[1][i]
end)
M.islice = mty.doc[[
islice(t, starti, endi=#t): iterate over slice.
  Unlike other i* functions, this ignores length
  except as the default value of endi
]](function(t, starti, endi)
  return M.rawislice, {t, endi or #t}, (starti or 1) - 1
end)

M.ilast = mty.doc[[
iend(t, starti, endi=-1): get islice from the end.
  starti and endi must be negative.

Example:
  iend({1, 2, 3, 4, 5}, -3, -2) -> 3, 4
]](function(t, starti, endi)
  local len = #t; endi = endi and math.min(len, len + endi + 1) or len
  return M.rawislice, {t, endi}, math.min(len - 1, len + starti)
end)

M.itable = mty.doc[[convert (_, v) iterator into a table by pushing]]
(function(it)
  local o = {}; for _, v in table.unpack(it) do add(o, v) end;
  return o
end)

M.kvtable = mty.doc[[convert (k, v) iterator into a table by setting]]
(function(it)
  local o = {}; for k, v in table.unpack(it) do o[k] = v end;
  return o
end)

M.ieq = mty.doc[[
Determine if two iterators are equal (ignores indexes)

Example:
  ieq({ipairs(a)}, {islice(b, 3, 7)})
]](function(aiter, biter)
  local afn, astate, ai, a = table.unpack(aiter)
  local bfn, bstate, bi, b = table.unpack(biter)
  while true do
    ai, a = afn(astate, ai); bi, b = bfn(bstate, bi)
    if not mty.eq(a, b) then return false end
    if a == nil         then return true end
  end
end)

-- reverse a list-like table in-place
M.reverse = function(t)
  local l = #t; for i=1, l/2 do
    t[i], t[l-i+1] = t[l-i+1], t[i]
  end
  return t
end

M.extend = function(t, vals)
  for _, v in ipairs(vals) do add(t, v) end; return t
end
M.update = function(t, add)
  for k, v in pairs(add) do t[k] = v end; return t
end
M.updateKeys = function(t, add, keys)
  for _, k in ipairs(keys) do t[k] = add[k] end; return t
end
M.orderedKeys = mty.orderedKeys

M.popk = function(t, key) -- pop key
  local val = t[key]; t[key] = nil; return val
end


-- pop multiple keys, pops(t, {'a', 'b'})
M.pops = function(t, keys)
  local o = {}
  for _, k in ipairs(keys) do o[k] = t[k]; t[k] = nil end
  return o
end

M.drain = function(t, len)
  local out = {}
  for i=1, M.min(#t, len) do add(out, pop(t)) end
  return M.reverse(out)
end

M.getOrSet = function(t, k, newFn)
  local v = t[k]; if v then return v end
  v = newFn(t, k); t[k] = v
  return v
end

local keyPath
keyPath = mty.doc[[keyPath(t, 'a', 2, 'c') -> t.a[2].c]]
(function(t, ...)
  if(nil == ...) then return t end
  return keyPath(t[...], select(2, ...))
end)
M.keyPath = keyPath

local tryPath; tryPath = mty.doc[[
tryPath(t, 'a', 2, 'c') -> t.a?[2]?.c
Looks up the values at the path, returning nil if any are nil.
]](function(t, ...)
  if(nil == (...)) then return t end
  local v = t[...]; if v == nil then return end
  return tryPath(v, select(2, ...))
end)
M.tryPath = tryPath

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

M.popit = mty.doc[[
popit(t, i) -> t[i]  -- also, the length of t is reduced by 1

popit (aka pop-index-top) will return the value at t[i], replacing it with the
value at the end (aka top) of the list.

if i > #t returns nil and doesn't affect the size of the list.
]](function(t, i)
  local len = #t; if i > len then return end
  local o = t[i]; t[i] = t[len]; t[len] = nil
  return o
end)

M.walk = mty.doc[[walk(tbl, fieldFn, tableFn, maxDepth, state)
Walk the table up to depth maxDepth (or infinite if nil).

fieldFn(key, value, state)  -> stop  is called for every non-table value.
tableFn(key, tblValue, state) -> stop is called for every table value

If tableFn stop==ds.SKIP (i.e. 'skip') then that table is not recursed.
Else if stop then the walk is halted immediately
]](function(t, fieldFn, tableFn, maxDepth, state)
  if maxDepth then
    maxDepth = maxDepth - 1; if maxDepth < 0 then return end
  end
  for k, v in pairs(t) do
    if type(v) == 'table' then
      if tableFn then
        k = tableFn(k, v, state); if k then
          if k == M.SKIP then goto skip end
          return
        end
      end
      M.walk(v, fieldFn, tableFn, maxDepth, state)
    elseif fieldFn and fieldFn(k, v, state) then return end
    ::skip::
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

function M.fileWithText(path, text, mode)
  local f = mty.assertf(
    io.open(path, mode or 'w+'), 'invalid %s', path)
  f:write(text); f:flush(); f:seek'set'
  return f
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
M.lineschunk = mty.doc'convert lines-like table into chunk for eval'
(function(dat)
  local i = 1
  return function() -- alternates between next line and newline
    local o = '\n'; if i < 0 then i = 1 - i
    else  o = dat[i];             i =   - i end
    if o == '' then assert(i < 0); o = '\n'; i = 1 - i end
    return o
  end
end)
M.eval = function(chunk, env, name) -- Note: not typed
  assert(type(env) == 'table')
  name = name or pkg.callerSource()
  local e, err = load(chunk, name, 't', env)
  if err then return false, err end
  return pcall(e)
end

---------------------
-- Low-level Types
-- These are generally used to create other types and are
-- not used directly. See lua documentation on specific
-- usage.

M.WeakK = mty.doc[[Weak key table, see docs on '__mode']]
(setmetatable(
  {__name='WeakK', __mode='k'}, {
  __name='Ty<WeakK>', __call=mty.newUnchecked,
}))
M.WeakV = mty.doc[[Weak value table, see docs on '__mode']]
(setmetatable(
  {__name='WeakV', __mode='v'}, {
  __name='Ty<WeakV>', __call=mty.newUnchecked,
}))

M.WeakKV = mty.doc[[Weak key+value table, see docs on '__mode']]
(setmetatable(
  {__name='WeakKV', __mode='kv'}, {
  __name='Ty<WeakKV>', __call=mty.newUnchecked,
}))

---------------------
-- Sentinal, none type, bool() and empty table

local _si=function() error('invalid operation on sentinel', 2) end
M.newSentinel = mty.doc[[newSentinel(name, ty_, metatable)
Use to create a "sentinel type". Return the metatable used.

Sentinels are "single values" commonly used for things like: none, empty, EOF, etc.
They have most metatable methods disallowed and are locked down. Override/add
whatever methods you want by passing your own metatable.
]](function(name, ty_, mt)
  mt = M.update({
    __name=name, __eq=rawequal, __tostring=function() return name end,
    __index=_si, __newindex=_si, __len=_si, __pairs=_si, __ipairs=_si,
  }, mt or {})
  return setmetatable(ty_, mt)
end)

-- TODO: if I remove this space then 'help ds none' is
-- missing a newline (???)
local noneDoc = [[
none: "set as none" vs nil aka "unset"

none is a sentinel value. Use it in APIs where there is an
"unset but none" such as JSON's "null".
]]
M.none = M.newSentinel('none', {}, {__metatable='none'})
mty.addNativeTy(M.none, {doc=noneDoc})

M.bool = mty.doc[[convert to boolean (none aware)]]
(function(v) return not rawequal(M.none, v) and v and true or false end)

-- An immutable empty table
M.empty = setmetatable({}, {
  __newindex = function() error('mutate ds.empty', 2) end,
  __metatable = 'table',
})

---------------------
-- imm(myTy) and Imm{...} table

M._IMM_FIELD = '! DO-NOT-SET !'; M.IMM_DEFAULTS = {
  __index=function(self, k)
    local x = self[M._IMM_FIELD][k]; if x ~= nil then return x end
    return mty.indexChecked(self, k)
  end,
  __newindex=function()  error('set on immutable type', 2) end,
  __pairs=function(v)    return pairs(v[M._IMM_FIELD]) end,
  __ipairs=function(v)   return ipairs(v[M._IMM_FIELD]) end,
  __len=function(v)      return #v[M._IMM_FIELD] end,
}
M.newImmChecked = function(ty_, t)
  return setmetatable({[M._IMM_FIELD]=t}, ty_)
end
M.newImm = mty.getCheck() and M.newImmChecked or mty.new

M.immChecked = mty.doc[[
imm(MyType): make a type (record, etc) mostly-immutable.
We actually hide the table inside [ds._IMM_FIELD], but nobody needs
to know that!
Example:
  myTy = imm(record'myTy')
    :field'f1'
  -- Important: use ds.newImm (not metaty.new)
  :new(function(ty_, t) ...; return ds.newImm(ty_, t) end)]]
(function(ty_)
  getmetatable(ty_).__call=M.newImm
  M.update(ty_, M.IMM_DEFAULTS)
  return ty_
end)
M.imm = mty.getCheck() and M.immChecked or mty.identity

M.ImmChecked = mty.doc[[Imm{hi='immutable'}: immutable table.
In all ways this will look like a normal table:
  metaty.ty(Imm{}) == 'table'
  however: getmetatable(Imm{}) == 'table' -- instead of nil

Caveats: see ds.imm.]]
(M.immChecked(mty.rawTy'Imm'))
M.ImmChecked.__index=function(v, k) return v[M._IMM_FIELD][k] end
M.ImmChecked.__metatable = 'table'
M.Imm = mty.getCheck() and M.ImmChecked or mty.identity

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
  assert(math.floor(t.s) == t.s,   'non-int seconds')
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
M.Duration.__add = function(self, r)
  assert(mty.ty(r) == M.Duration)
  local s, ns = durationSub(self.s, self.ns, -r.s, -r.ns)
  return M.Duration(s, ns)
end
M.Duration.__lt = function(self, o)
  if self.s < o.s then return true end
  return self.ns < o.ns
end
M.Duration.__fmt = nil
M.Duration.__tostring = function(self) return self:asSeconds() .. 's' end

M.DURATION_ZERO = M.Duration(0, 0)

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
M.Epoch.__lt = function(self, o)
  if self.s < o.s then return true end
  return self.ns < o.ns
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
-- module `ll` is for handling a linked-lists as a table
-- and is more performant.
-- LL is a data object for LL's and may be removed.

M.ll = mty.doc[[Tiny linked-list module.
  This uses indexes to track linked-lists, making it
  extremely memory efficient and fairly performant.

-- 1 [-> ...]            linked list with just root
local llp, lln, llv = {0}, {0}, {}

-- 1 -> 2 [-> 1...]      append 2 to root
ll.push(llp, lln, 1, 2); llv[2] = 'value@2'

-- 3 -> 1 -> 2 [-> 3...] prepend 3 to root
ll.budge(llp, lln, 1, 3); llv[3] = 'value@3'

-- 3 -> 1 [-> 3...]      pop 2
ll.pop(llp, lln, 2)
]]{}

-- get initial llp, lln, llv
function M.ll.empty() return {1}, {1}, {} end

-- a -> node -> b  ==> a -> b
function M.ll.pop(prev, nxt, node)
  local a, b = prev[node], nxt[node]
  nxt[a], prev[b] = b, a
end

-- node -> b  ==>  node -> a -> b
function M.ll.push(prev, nxt, node, a)
  local b = nxt[node]
  nxt[node],  nxt[a]  = assert(a), b
  prev[b],    prev[a] = a, node
end

-- b -> node ==>  b -> a -> node
function M.ll.budge(prev, nxt, node, a)
  local b = prev[node]
  nxt[b],     nxt[a]  = a, node
  prev[node], prev[a] = a, b
end

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

---------------------
-- Binary Search

local function _bs(t, v, cmp, si, ei)
  if ei <= si + 1 then -- cannot narrow further
    return cmp(t[ei], v) and ei
        or cmp(t[si], v) and si or (si - 1)
  end
  local mi = (si + ei) // 2
  if cmp(t[mi], v) then return _bs(t, v, cmp, mi, ei)
  else                  return _bs(t, v, cmp, si, mi - 1) end
end

M.binarySearch = mty.doc[[
binarySearch(t, v, cmp, si, ei) -> i
  cmp = ds.lte by default
  si = start index, default=1
  ei = end index,   default=#t

Search the sorted table, return i such that:
* cmp(t[i], v) returns true  for indexes <= i
* cmp(t[i], v) returns false for indexes >  i

If you want a value perfectly equal then check equality
on the resulting index.
]](function(t, v, cmp, si, ei)
  return _bs(t, v, cmp or M.lte, si or 1, ei or #t)
end)

---------------------
-- Binary Tree

M.bt = mty.docTy({}, [[
ds.bt: indexed table as Binary Tree.
These functions treat an indexed table as a binary tree
where root is at index=1.
]])
function M.bt.left(t, i)    return t[i * 2]     end
function M.bt.right(t, i)   return t[i * 2 + 1] end
function M.bt.parent(t, i)  return t[i // 2]    end
function M.bt.lefti(t, i)   return   i * 2      end
function M.bt.righti(t, i)  return   i * 2 + 1  end
function M.bt.parenti(t, i) return   i // 2     end

---------------------
-- Directed Acyclic Graph

M.dag = mty.docTy({}, "Functions for working with directed acyclic graphs.")

local function _dagSort(st, name, parents)
  if st.visited[name] then return end; st.visited[name] = true
  if parents then for _, pname in ipairs(parents) do
    _dagSort(st, pname, st.depsMap[pname])
  end end
  add(st.out, name)
end

M.dag.sort = mty.doc[[
dag.sort(depsMap) -> sortedDeps

Sort the directed acyclic graph. depsMap must behave like a table which:

  for pairs(depsMap) -> nodeName, ...
  depsMap[nodeName]  -> nodeDeps (list)

If depsMap is a map of pkg -> depPkgs then the result is the order the pkgs
should be built.

Note: this function does NOT detect cycles.
]](function(depsMap)
  local state = {depsMap=depsMap, out={}, visited={}}
  for name, parents in pairs(depsMap) do
    _dagSort(state, name, parents)
  end
  return state.out
end)

M.dag.reverseMap = mty.doc[[
dag.reverseMap(childrenMap) -> parentsMap (or vice-versa)
]](function(childrenMap)
  local pmap = {}
  for pname, children in pairs(childrenMap) do
    M.getOrSet(pmap, pname, M.emptyTable)
    if children then for _, cname in ipairs(children) do
      add(M.getOrSet(pmap, cname, M.emptyTable), pname)
    end end
  end
  return pmap
end)

M.dag.missing = mty.doc[[
dag.missing(depsMap) -> missingDeps

Given a depsMap return missing deps (items in a deps with no name).
]](function(depsMap)
  local missing = {}; for n, deps in pairs(depsMap) do
    for _, dep in ipairs(deps) do
      if not depsMap[dep] then missing[dep] = true end
    end
  end
  return missing
end)

---------------------
-- BiMap
M.BiMap = mty.doc[[
BiMap{} -> biMap: Bidirectional Map
maps both key -> value and value -> key
must use `:remove` (instead of `bm[k] = nil` to handle deletions.

Note that pairs() will return BOTH directions (in an unspecified order)
]](mty.record'BiMap')
:new(function(ty_, t)
  local keys = {}; for k, v in pairs(t) do
    if not t[v] then add(keys, k) end
  end
  for _, k in pairs(keys) do t[t[k]] = k end
  return mty.newUnchecked(ty_, t)
end)
M.BiMap.__index = mty.indexUnchecked
M.BiMap.__newindex = function(t, k, v)
  mty.pnt('?? BiMap newindex', k, v)
  rawset(t, k, v); rawset(t, v, k)
end
M.BiMap.__fmt = nil
M.BiMap.remove = function(t, k)
  local v = t[k]; t[k] = nil; t[v] = nil
end

---------------------
-- Fifo Buffer
M.Deq = mty.doc[[
Deq() -> Deq, a deque

Main methods:
  pushLeft()  pushRight()
  popLeft()   popRight()

Calling it is the same as popLeft (use as iterator)
]](mty.record'Deq')
  :field('right', 'number')  :field('left', 'number')
:new(function(ty_) return mty.new(ty_, {right=0, left=1}) end)
M.Deq.pushRight = function(deq, val)
  local r = deq.right + 1; deq[r] = val; deq.right = r
end
M.Deq.pushLeft = function(deq, val)
  local l = deq.left - 1;  deq[l] = val; deq.left = l
end
M.Deq.popLeft = function(deq)
  local l = deq.left; if l > deq.right then return nil end
  local val = deq[l]; deq[l] = nil; deq.left = l + 1
  return val
end
M.Deq.popRight = function(deq)
  local r = deq.right; if deq.left > r then return nil end
  local val = deq[r]; deq[r] = nil; deq.right = r - 1
  return val
end
M.Deq.push = M.Deq.pushRight
M.Deq.__len = function(d) return d.right - d.left + 1 end
M.Deq.pop = M.Deq.popLeft
M.Deq.__call = M.Deq.pop

return M
