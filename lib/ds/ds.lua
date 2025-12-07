local G = G or _G

-- ds: data structures and algorithms
local M = G.mod and G.mod'ds' or {}


local mty = require'metaty'
local fmt = require'fmt'

local next = G.next
local getmt = G.getmetatable
local push, pop, sfmt    = table.push, table.remove, string.format
local sfind = string.find
local move, sort, unpack = table.move, table.sort, table.unpack
local concat             = table.concat
local ulen, uoff     = utf8.len, utf8.offset
local min, max = math.min, math.max
local xpcall, traceback = xpcall, debug.traceback
local resume = coroutine.resume
local getmethod = mty.getmethod
local EMPTY = {}


--- pure-lua bootstrapped library (mainly for bootstrap.lua)
M.B = mty.mod'M.B'

--- concatenate varargs.
M.B.string_concat = function(sep, ...) --> string
  return concat({...}, sep)
end

--- push v onto table, returning index.
M.B.push = function(t, v) --> index
  local i = #t + 1; t[i] = v; return i
end

--- return t with the key/vals of add inserted
M.B.update = function(t, add) --> t
  for k,v in pairs(add) do t[k] = v end
  return t
end

--- update ignoring t.__pairs.
local function updateRaw(t, add)
  for k,v in next, add do
    t[k] = v
  end
  return t
end

local lib
if G.NOLIB then lib = M.B
else
  lib = require'ds.lib'
  updateRaw = lib.update
end

--- concatenate the string arguments.
M.sconcat = lib.string_concat --(sep, ...) --> string

--- push the value onto the end of the table, return the index.
M.push    = lib.push --(t, v) --> index

-- add missing globals
string.concat = rawget(string, 'concat') or lib.string_concat
table.update  = rawget(table, 'update')  or lib.update
table.push    = rawget(table,  'push')   or lib.push
local push, sconcat = M.push, M.sconcat

local sconcat = string.concat
local tupdate = table.update

M.PlainStyler = mty'PlainStyler' {}

------------------
-- DS psudo-metaevents
-- these use new "metaevent" (similar to __len) that tables can override

--- if t is a table returns t.__name or '?'
M.name = function(t) --> string
  if not type(t) == 'table' then return end
  local mt = getmt(t)
end

--- insert values into list at index i.
--- Uses [$inset] method if available.
--- rmlen, if provided, will cause [$t[i:i+rmlen]] to be removed first
---
--- inset is like an extend but the items are insert at any place in the array.
--- The rmlen will also remove a certain number of items.
M.inset = function(t, i, values, rmlen) --> nil
  if getmt(t) then return t:inset(i, values, rmlen) end
  -- impl notes, there are two modes:
  -- * we want to keep some values after i: we cache those values then shift in
  -- * we don't want to keep values after i: we shift in the values and clear
  --   the rest
  rmlen = rmlen or 0; local tlen, vlen = #t, #values
  if tlen - i - rmlen >= 0 then -- we want to keep some values >= i
    local cache = move(t, i + rmlen, tlen, 1, {})
    move(values, 1, max(vlen, tlen - i + 1), i, t)
    move(cache, 1, #cache, i + vlen, t)
    return
  end
  -- not keeping values >= i
  move(values, 1, max(vlen, rmlen), max(1, i + 1 - rmlen), t)
end

---------------------
-- Pseudo Types

--- the only four non-mutable data types in lua
local CONCRETE_TYPES = {
  ['nil']=true, boolean=true, number=true, string=true
}

-- return true if the value is "plain old data".
--
-- Plain old data is defined as any concrete type or a table with no metatable
-- and who's pairs() are only POD.
local isPod; isPod = function(v, mtFn)
  local ty = type(v)
  if ty == 'table' then
    local mt = getmt(v)
    if mt then return (mtFn or retTrue)(v, mt) end
    for k, v in pairs(v) do
      if not (isPod(k, mtFn) and isPod(v, mtFn)) then
        return false
      end
    end
    return true
  end
  return CONCRETE_TYPES[ty]
end
M.isPod, M.CONCRETE_TYPES = isPod, CONCRETE_TYPES

-----------------
-- Utility

M.SKIP      = 'skip'
M.noop      = function() end
M.nosupport = function() error'not supported' end
M.iden      = function(...) return ... end -- identity function
M.retTrue   = function() return true  end
M.retFalse  = function() return false end
M.newTable  = function() return {}    end
M.eq        = function(a, b) return a == b end

local retTrue = M.retTrue

M.srcloc = function(level) --> "/path/to/dir/file.lua:10"
  local info = debug.getinfo(2 + (level or 0), 'Sl')
  local loc = info.source; if loc:sub(1,1) ~= '@' then return end
  return loc:sub(2)..':'..info.currentline
end
M.shortloc = function(level) --> "dir/file.lua:10"
  local info = debug.getinfo(2 + (level or 0), 'Sl')
  local loc = info.source; if loc:sub(1,1) ~= '@' then return end
  -- Get only the dir/file.lua. If no dir, get just file.lua.
  loc = loc:match'^@.-([^/]*/[^/]+)$' or loc:sub(2)
  return loc..':'..info.currentline
end
M.srcdir = function(level) --> "/path/to/dir/"
  return M.srcloc(1 + (level or 0)):match'^(.*/)[^/]+$'
end

M.coroutineErrorMessage = function(cor, err) --> string
  return sconcat('',
    'Coroutine error: ', debug.stacktraceback(cor, err), '\n',
    'Coroutine failed!')
end

---------------------
-- Order checking functions
M.isWithin = function(v, min, max) --> bool
  local out = (min <= v) and (v <= max)
  return out
end
M.lt  = function(a, b) return a < b end
M.gt  = function(a, b) return a > b end
M.lte = function(a, b) return a <= b end
local lte = M.lte
M.bound = function(v, min, max) --> value within [min,max]
  return ((v>max) and max) or ((v<min) and min) or v
end
M.sort2 = function(a, b) --> (small, large)
  if a <= b then return a, b end; return b, a
end
M.repr = function(v) return sfmt('%q', v) end

---------------------
-- Number Functions
M.isEven = function(a) return a % 2 == 0 end --> bool
M.isOdd  = function(a) return a % 2 == 1 end --> bool
M.decAbs = function(v) --> number
  if v == 0 then return 0 end
  return ((v > 0) and v - 1) or v + 1
end

---------------------
-- String Functions

-- Concatenate all values in ..., calling tostring on them
-- if necessary.
-- This has several differences than table.concat:[+
-- * it does not require allocating a table to be called.
-- * it automatically calls tostring on the arguments.
-- ]
--
-- This function is most useful if you have a known number
-- of arguments or ... which you want to concatenate.
M.concat = string.concat--(sep, ...) --> string

--- return the string if it is only uppercase letters
M.isupper = function(c) return c:match'^%u+$' end --> string?

--- return the string if it is only lowercase letters
M.islower = function(c) return c:match'^%l+$' end --> string?

M.trim = function(subj, pat, index) --> string
  pat = pat and ('^'..pat..'*(.-)'..pat..'*$') or '^%s*(.-)%s*$'
  return subj:match(pat, index)
end

--- find any of a list of patterns. Return the match [$start, end] as well as
--- the [$index, pat] of the pattern matched.
M.find = function(subj, pats, si, plain) --> (ms, me, pi, pat)
  si = si or 1
  for pi, p in ipairs(pats) do
    local ms, me = sfind(subj, p, si, plain)
    if ms then return ms, me, pi, p end
  end
end

--- split strings
M.split = mty.split         --(s, sep) --> strIter
M.splitList = function(...) --(s, sep) --> list
  local t = {}; for _, v in mty.split(...) do push(t, v) end
  return t
end

--- trim the end of the string by removing pat (default='%s')
M.trimEnd = function(subj, pat, index) --> string
  pat = pat and ('^(.-)'..pat..'*$') or '^(.-)%s*$'
  return subj:match(pat, index)
end

--- Squash a string: convert all whitespace to repl (default=' ').
M.squash = function(s, repl) return s:gsub('%s+', repl or ' ') end --> string

--- utf8 sub. If len is pre-computed you can pass it in for better performance.
M.usub = function(s, si, ei, len)
  ei = ei or -1
  if si < 0 then len = len or ulen(s); si = len + si + 1 end
  local so = uoff(s, si)
  if not so then return '' end
  if ei < 0 then
    if ei == -1 then return s:sub(so) end
    len = len or ulen(s); ei = len + ei + 1
  end
  local eo = uoff(s, ei - si + 2, so) -- offset of character after ei
  return s:sub(so, eo and (eo - 1) or nil)
end

--- A way to declare simpler mulitline strings which: [+
--- * ignores the first/last newline if empty
--- * removes leading whitespace equal to the first
---   line (or second line if first line has no indent)
--- ]
--- Example: [{## lang=lua}
--- local s = require'ds'.simplestr
--- local mystr = s[[
---   this is
---     a string.
--- ]]
--- T.eq('this is\n  a string.', mystr)
--- ]##
M.simplestr = function(s)
  local i, out, iden, spcs = 1, {}, nil
  for _, line in M.split(s, '\n') do
    spcs = line:match'^%s*'
    if iden then -- later lines, iden already set
      assert((#spcs == #line) or (#spcs >= #iden), 'invalid indent')
      push(out, line:sub(#iden + 1))
    else -- set iden from line 1 (if exists) or line 2
      iden = (i > 1 or spcs ~= '') and spcs or nil
      push(out, line:sub(#spcs + 1))
    end
    i = i + 1
  end
  return concat(out, '\n')
end

--- Convert integer to binary representation (0's and 1's) [+
--- * width will be the number of bits.
--- * sep4 will be used to separate every 4 bits, set to
---   nil to disable.
--- ]
M.bin = function(uint, width--[[8]], sep4--[['_']]) --> str
  width = width or 8
  if sep4 == nil then sep4 = '_' end
  local str = {}
  for w=0,width-2 do
    push(str, tostring(1 & uint))
    uint = uint >> 1
    if sep4 and w % 4 == 3 then push(str, sep4) end
  end
  push(str, tostring(1 & uint))
  M.reverse(str)
  return concat(str, '')
end

---------------------
-- Table Functions

--- [$t[k]] if t is a raw table, else [$getmetatable(t).get(t, k)]
---
--- This lets many types be substitutable for raw-tables in some APIs (i.e. lines).
M.get = function(t, k) --> value
  if getmt(t) then return t:get(k) end
  return t[k]
end
local get = M.get

--- [$t[k] = v] if t is a raw table, else [$getmetatable(t).set(t, k, v)]
---
--- This lets many types be substitutable for raw-tables in some APIs (i.e. lines).
M.set = function(t, k, v)
  if getmt(t) then return t:set(k, v) end
  t[k] = v
end

M.isEmpty = function(t) return t == nil or next(t) == nil end

--- the full length of all pairs
--- ["WARNING: very slow, requires iterating the whole table]
M.pairlen = function(t) --> int
  local l = 0; for _ in pairs(t) do l = l + 1 end; return l
end

--- sort table and return it.
--- Eventually this may use the [$__sort] metamethod
M.sort = function(t, fn) sort(t, fn); return t end --> t

--- sort t and remove anything where [$rmFn(v1, v2)]
--- (normally rmFn is [$ds.eq])
M.sortUnique = function(t, sortFn, rmFn) --> t
  sort(t, sortFn); rmFn = rmFn or M.eq
  local i, len, iv, kv = 1, #t
  for k=2,len do
    iv, kv = t[i], t[k]
    if not rmFn(iv, kv) then
      i = i + 1; t[i] = kv
    end
    k = k + 1
  end
  move(EMPTY, i+1, len, i+1, t)
  return t
end

--- get index, handling negatives
M.geti = function(t, i) --> t[i]
  return (i >= 0) and t[i] or t[#t + i + 1]
end
M.last = function(t) return t[#t] end

--- get the first (and assert only) element of the list
M.only = function(t) --> t[1]
  local l = #t; fmt.assertf(l == 1, 'not only: len=%s', l)
  return t[1]
end

--- get only the values of pairs(t) as a list
M.values = function(t) --> list
  local vals = {}; for _, v in pairs(t) do push(vals, v) end
  return vals
end

-- get only the keys of pairs(t) as a list
M.keys = function(t) --> list
  local keys = {}; for k in pairs(t) do push(keys, k) end
  return keys
end

--- next(t, key) but with indexes
M.inext = ipairs{} --(t, i) --> (i+1, v)
local inext = M.inext

--- inext but reversed.
M.iprev = function(t, i) --> (t, i) --> (i-1, v)
  if i > 1 then return i - 1, t[i - 1] end
end

--- ipairs reversed
M.ireverse = function(t) return M.iprev, t, #t + 1 end --> iter

M.rawislice = function(state, i) --> (i+1, v)
  i = i + 1; if i > state[2] then return end
  return i, state[1][i]
end

-- islice(t, starti, endi=#t): iterate over slice.
--   Unlike other i* functions, this ignores length
--   except as the default value of endi
M.islice = function(t, starti, endi) --> iter[starti:endi]
  if endi then
    return M.rawislice, {t, endi}, (starti or 1) - 1
  end
  return inext, t, (starti or 1) - 1
end

M.slice = function(t, starti, endi) --> list[starti:endi]
  local sl = {}
  for i=starti or 1,endi or #t do push(sl, t[i]) end
  return sl
end

--- iend(t, starti, endi=-1): get islice from the end.
---   starti and endi must be negative.
---
--- Example: [$iend({1, 2, 3, 4, 5}, -3, -2) -> 3, 4]
M.ilast = function(t, starti, endi) --> iter[starti:endi]
  local len = #t; endi = endi and min(len, len + endi + 1) or len
  return M.rawislice, {t, endi}, min(len - 1, len + starti)
end

--- Return true if two list-like tables are equal.
M.ieq = function(a, b)
  if #a ~= #b then return false end
  for i=1,#a do if a[i] ~= b[i] then return false end end
  return true
end

--- reverse a list-like table in-place
M.reverse = function(t) --> t (reversed)
  local l = #t; for i=1, l/2 do
    t[i], t[l-i+1] = t[l-i+1], t[i]
  end
  return t
end

M.extend = function(t, l) --> t: move vals to end of t
  if getmt(t) then return t:extend(l) end
  return move(l, 1, #l, #t + 1, t)
end
local extend = M.extend
M.defaultExtend = function(r, l) --> r
  local rset = getmt(r) and assert(r.set) or rawset
  local lget = getmt(l) and assert(l.get) or rawget
  local rlen = #r
  for k=1,#l do rset(r, rlen+k, lget(l,k)) end
  return r
end

-- Clear list-like elements of table.
-- default is all of it, but you can also specify a specific
-- start index and length.
M.clear = function(t, si, len) --> t
  -- TODO: (len or #t) - si + 1
  return move(EMPTY, 1, len or #t, si or 1, t)
end
-- append one or more values to t
M.add = function(t, ...) --> t
  local tend = #t
  for i=1,select('#', ...) do t[tend + i] = select(i, ...) end
  return t
end
-- make t's index values the same as r's
M.replace = function(t, r) --> t
  return move(r, 1, max(#t, #r), 1, t)
end
--- return t with the key/vals of add inserted
M.update = M.B.update
--- return new list which contains all elements inserted in order
M.flatten = function(...)
  local t, len = {}, select('#', ...)
  for i=1,len do extend(t, select(i, ...)) end
  return t
end

--- like update but only for specified keys
M.updateKeys = function(t, add, keys) --> t
  for _, k in ipairs(keys) do t[k] = add[k] end; return t
end
M.orderedKeys = function(t, cmpFn) --> keys
  local keys = {}; for k in pairs(t) do push(keys, k) end
  sort(keys, cmpFn)
  return keys
end
--- adds all [$key=index] to the table so the keys can
--- be iterated using [$for _, k in ipairs(t)]
M.pushSortedKeys = function(t, cmpFn) --> t
  local keys = M.orderedKeys(t, cmpFn)
  for i, k in ipairs(keys) do t[i] = k end
  return t
end

--- recursively update t with add. This will call update on inner tables as
--- well.
--- ["Note: treats list indexes as normal keys (does not append)]
M.merge = function(t, add) --> t
  for k, v in pairs(add) do
    local ex = t[k] -- existing
    if type(ex) == 'table' and type(v) == 'table' then
      M.merge(ex, v)
    else t[k] = v end
  end
  return t
end

M.popk = function(t, key) --> t[k]: pop key
  local val = t[key]; t[key] = nil; return val
end

--- return len items from the end of [$t], removing them from [$t]
M.drain = function(t, len--[[#t]]) --> table
  local out = {}; for i=1, min(#t, len) do push(out, pop(t)) end
  return M.reverse(out)
end

M.getOrSet = function(t, k, newFn) --> t[k] or newFn()
  local v = t[k]; if v ~= nil then return v end
  v = newFn(t, k); t[k] = v
  return v
end

M.setIfNil = function(t, k, v) --> nil
  if t[k] == nil then t[k] = v end
end
M.emptyTable = function() return {} end

--- remove (mutate) the left side of the table (list).
--- noop if rm is not exactly equal to the left side.
M.rmleft = function(t, rm, eq--[[ds.eq]]) --> t (mutated)
  eq = eq or M.eq
  for i, v in ipairs(rm) do
    if not t[i] or not eq(v, t[i]) then
      return
    end
  end
  local l, rl = #t, #rm
  move(t,     rl + 1, l,  1, t) -- move to start
  move(EMPTY, 1,      rl, l - rl + 1, t) -- clear end
  return t
end

--- used with ds.getp and ds.setp. Example [{## lang=lua}
---   local dp = require'ds'.dotpath
---   ds.getp(t, dp'a.b.c')
--- ]##
M.dotpath = function(dots) --> list split by '.'
  local p = {}; for v in dots:gmatch'[^%.]+' do push(p, v) end
  return p
end

--- get the value at the path or nil if the value or any
--- intermediate table is missing.
--- [{## lang=lua}
---   get(t, {'a', 2, 'c'})  -> t.a?[2]?.c?
---   get(t, dotpath'a.b.c') -> t.a?.b?.c?
--- ]##
M.getp = function(t, path) --> value? at path
  for _, k in ipairs(path) do
    t = t[k]; if t == nil then return nil end
  end
  return t
end

--- same as ds.getp but uses [$rawget]
M.rawgetp = function(t, path) --> value? at path
  for _, k in ipairs(path) do
    t = rawget(t, k); if t == nil then return nil end
  end
  return t
end

--- set the value at path using newFn (default=ds.newTable) to create
--- missing intermediate tables.
--- [{## lang=lua}
--- set(t, dotpath'a.b.c', 2) -- t.a?.b?.c = 2
--- ]##
M.setp = function(d, path, value, newFn) --> nil
  newFn = newFn or M.emptyTable
  local len = #path; assert(len > 0, 'empty path')
  for i=1,len-1 do d = M.getOrSet(d, path[i], newFn) end
  d[path[len]] = value
end

M.indexOf = function(t, find) --> int
  for i, v in ipairs(t) do
    if v == find then return i end
  end
end

M.indexOfPat = function(strs, pat) --> int
  for i, s in ipairs(strs) do if s:find(pat) then return i end end
end

--- popit (aka pop-index-top) will return the value at [$t[i]], replacing it
--- with the value at the end (aka top) of the list.
---
--- if [$i > #t] returns nil and doesn't affect the size of the list.
M.popit = function(t, i) --> t[i] and length of t is reduced by 1
  local len = #t; if i > len then return end
  local o = t[i]; t[i] = t[len]; t[len] = nil
  return o
end

--- Walk the table up to depth maxDepth (or infinite if nil) [+
--- * [$fieldFn(key, value, state)    -> stop] is called for every non-table value.
--- * [$tableFn(key, tblValue, state) -> stop] is called for every table value
--- ]
---
--- If tableFn [$stop==ds.SKIP] (i.e. 'skip') then that table is not recursed.
--- Else if stop then the walk is halted immediately
M.walk = function(t, fieldFn, tableFn, maxDepth, state) --> nil
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
end

--- A typo-safe table, typically used in libraries for storing constants.
---
--- Adding keys is always allowed but getting non-existant keys is an error.
M.TypoSafe = mty'TypoSafe'{}
getmt(M.TypoSafe).__call = mty.constructUnchecked
getmt(M.TypoSafe).__index = mty.index
M.TypoSafe.__newindex = nil


---------------------
-- Untyped Functions

--- Copy list-elements only
M.icopy = function(t) --> list
  if getmt(t) then return t:icopy() end
  return move(t, 1, #t, 1, {})
end

M.defaultICopy = function(r)
  local t = {}; for i=1,#r do t[i] = r:get(i) end
  return t
end

--- Copy and update full table
M.copy = function(t, add) --> new t
  return setmetatable(
    add and updateRaw(updateRaw({}, t), add) -- copy+add
         or updateRaw({}, t)                 -- copy
    , getmt(t))
end

M.deepcopy = function(t) --> table
  local out = {}; for k, v in pairs(t) do
    if 'table' == type(v) then v = M.deepcopy(v) end
    out[k] = v
  end
  return setmetatable(out, getmt(t))
end

---------------------
-- File Functions
M.readPath = function(path) --!> string
  local f, out, err = assert(io.open(path))
  out, err = f:read('a'); f:close()
  return assert(out, err)
end

M.writePath = function(path, text) --!> nil
  local f = fmt.assertf(io.open(path, 'w'), 'invalid %s', path)
  local out, err = f:write(text); f:close(); assert(out, err)
end

---------------------
-- Source Code Functions

--- convert lines-like table into chunk for eval
M.lineschunk = function(dat) --> iter()
  local i = 1
  return function() -- alternates between next line and newline
    local o = '\n'; if i < 0 then i = 1 - i
    else  o = get(dat,i);         i =   - i end
    if o == '' then assert(i < 0); o = '\n'; i = 1 - i end
    return o
  end
end

--- evaluate lua code
M.eval = function(chunk, env, name) --> (ok, ...)
  assert(type(env) == 'table')
  if not name then
    local i = debug.getinfo(3)
    name = sfmt('%s:%s', i.source, i.currentline)
  end
  local e, err = load(chunk, name, 't', env)
  if err then return false, err end
  return pcall(e)
end

---------------------
-- Low-level Types

--- Weak key table, see docs on [$__mode]
M.WeakK = setmetatable(
  {__name='WeakK', __mode='k'}, {
  __name='Ty<WeakK>', __call=mty.constructUnchecked,
})

--- Weak value table, see docs on [$__mode]
M.WeakV = setmetatable(
  {__name='WeakV', __mode='v'}, {
  __name='Ty<WeakV>', __call=mty.constructUnchecked,
})

--- Weak key+value table, see docs on [$__mode]
M.WeakKV = setmetatable(
  {__name='WeakKV', __mode='kv'}, {
  __name='Ty<WeakKV>', __call=mty.constructUnchecked,
})

--- Table that ignores new indexes. Used to disable caching in tests.
M.Forget = setmetatable(
  {__name='Forget', __newindex=M.noop},
  {__name='Ty<Forget>', __call=mty.constructUnchecked}
)

--- Table that errors on missing key
M.Checked = setmetatable(
  {__name='Checked', __metatable='table',
   __index=function(_, k) error('unknown key: '..k) end,
  },
  {__name='Ty<Checked>', __call=mty.constructUnchecked}
)


--- A slice of anything with start and end indexes.
--- ["Note: This object does not hold a reference to the object being
---   sliced.]
M.Slc = mty'Slc' {
  'si [int]: start index',
  'ei [int]: end index',
}
local Slc = M.Slc
M.Slc.__len = function(s) return s.ei - s.si + 1 end --> #s

--- return either a single (new) merged or two sorted Slcs.
M.Slc.merge  = function(a, b) --> first, second?
  if a.si > b.si     then a, b = b, a end -- fix ordering
  if a.ei + 1 < b.si then return a, b end -- check overlap
  return Slc{si=a.si, ei=max(a.ei, b.ei)}
end

M.Slc.__fmt = function(s, fmt) --> string
  fmt:write(sfmt('Slc[%s:%s]', s.si, s.ei))
end

---------------------
-- Sentinal, none type, bool()

local _si=function() error('invalid operation on sentinel', 2) end
--- [$sentinel(name, metatable)]
--- Use to create a "sentinel type". Return the (singular) instance.
---
--- Sentinels are "single values" commonly used for things like: none, empty, EOF, etc.
--- They have most metatable methods disallowed and are immutable down. Methods can
--- only be set by the provided metatable value.
M.sentinel = function(name, mt) --> NewType
  mt = M.update({
    __name=name, __tostring=function() return name end,
    __newindex=_si, __len=_si, __pairs=_si,
    __pairs = function() return M.noop end,
  }, mt or {})
  mt.__index = mt
  setmetatable(mt, {__name='Ty<'..name..'>', __index=mty.indexError})
  local S = setmetatable({}, mt)
  mt.__toPod   = function() return S end
  mt.__fromPod = function(_, pod, v)
    if v ~= S then error('expected '..name..' got '..type(v)) end
    return v
  end
  rawset(S, '__toPod', mt.__toPod)
  rawset(S, '__fromPod', mt.__fromPod)
  return S
end

--- none: "set as none" vs nil aka "unset"
---
--- none is a sentinel value. Use it in APIs where there is an
--- "unset but none" such as JSON's "null".
M.none = M.sentinel('none', {__metatable='none'})

--- convert to boolean (none aware)
M.bool = function(v) --> bool
  return not rawequal(M.none, v) and v and true or false
end

--- An immutable empty table
M.empty = setmetatable({}, {
  __newindex = function() error('mutate ds.empty', 2) end,
  __metatable = 'table',
})

--- Immutable table
M.Imm = mty'Imm' {}
local IMM_DATA = '<!imm data!>'
getmt(M.Imm).__call = function(T, t)
  return setmetatable({[IMM_DATA]=(next(t) ~= nil) and t or nil}, T)
end
M.Imm.__metatable = 'table'
M.Imm.__newindex = function() error'cannot modify Imm table' end
M.Imm.__index    = function(t, k)
  local d = rawget(t, IMM_DATA); return d and d[k]
end
M.Imm.__pairs    = function(t) return next, rawget(t, IMM_DATA) or t end
M.Imm.__len      = function(t)
  local d = rawget(t, IMM_DATA); return not d and 0 or #d
end

M.empty = M.Imm{}

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

local timeNew = function(T, s, ns)
  if ns == nil then return T:fromSeconds(s) end
  local out = {s=s, ns=ns}
  return setmetatable(assertTime(out), T)
end
local fromSeconds = function(ty_, s)
  local sec = math.floor(s)
  return ty_(sec, math.floor(NANO * (s - sec)))
end
local fromMs = function(ty_, s)     return ty_(s / 1000) end
local fromMicros = function(ty_, s) return ty_(s / 1000000) end
local asSeconds = function(time) return time.s + (time.ns / NANO) end

M.Duration = mty'Duration' {
  's[int]: seconds', 'ns[int]: nanoseconds',
}
getmt(M.Duration).__call = timeNew

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
M.Epoch = mty'Epoch' {
  's[int]: seconds', 'ns[int]: nanoseconds',
}
getmt(M.Epoch).__call = timeNew

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
M.Set = mty'Set'{}
M.Set.__newindex = nil
getmt(M.Set).__index = nil
getmt(M.Set).__call = function(T, t)
  local s = {}
  for _, k in ipairs(t) do s[k] = true end
  return mty.constructUnchecked(T, s)
end

M.Set.__fmt = function(self, f) --> nil
  f:write('Set', f.tableStart)
  local keys = {}; for k in ipairs(self) do push(keys, k) end
  sort(keys)
  if #keys > 1 then f:level(1) end
  for i, k in ipairs(keys) do
    f(k)
    if i < #keys then f:write(f.indexEnd) end
  end
  if #keys > 1 then f:level(-1) end
  f:write(f.tableEnd)
end

M.Set.__eq = function(self, t) --> bool
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

M.Set.union = function(self, s) --> Set
  local both = M.Set{}
  for k in pairs(self) do if s[k] then both[k] = true end end
  return both
end

--- items in self but not in s
M.Set.diff = function(self, s) --> Set
  local left = M.Set{}
  for k in pairs(self) do if not s[k] then left[k] = true end end
  return left
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

--- Search the sorted table, return i such that: [+
--- * [$cmp(t[i], v)] returns true  for indexes <= i
--- * [$cmp(t[i], v)] returns false for indexes >  i
--- ]
--- If you want a value perfectly equal then check equality
--- on the resulting index.
M.binarySearch = function(t, v, cmp, si--[[1]], ei--[[#t]]) --> index
  return _bs(t, v, cmp or lte, si or 1, ei or #t)
end

---------------------
-- Binary Tree

--- indexed table as Binary Tree.
--- These functions treat an indexed table as a binary tree
--- where root is at [$index=1]
M.bt = mod and mod'bt' or {}
M.bt.left = function(t, i)    return t[i * 2]     end
M.bt.right = function(t, i)   return t[i * 2 + 1] end
M.bt.parent = function(t, i)  return t[i // 2]    end
M.bt.lefti = function(t, i)   return   i * 2      end
M.bt.righti = function(t, i)  return   i * 2 + 1  end
M.bt.parenti = function(t, i) return   i // 2     end

---------------------
-- Directed Acyclic Graph

local function _dagSort(out, id, parentMap, visited) --> cycle?
  do -- detect cycles and whether we've already visited id.
    local v = visited[id]; if v then
      if type(v) == 'number' then  -- cycle detected
        push(visited, id);
        return M.slice(visited, v)
      end
      return -- already visited
    end
  end
  local info = require'ds.log'.info
  push(visited, id); visited[id] = #visited
  for _, pid in ipairs(
      fmt.assertf(parentMap[id], '%q missing parents', id)) do
    local cycle = _dagSort(out, pid, parentMap, visited)
    if cycle then return cycle end
  end
  push(out, id)
  pop(visited); visited[id] = true -- clear cycle detection
end

--- Sort the directed acyclic graph of ids + parentMap
--- to put children before the parents.
---
--- returns [$nil, cycle] in the case of a cycle
M.dagSort = function(ids, parentMap) --> sorted?, cycle?
  local out, visited, cycle = {}, {}
  for _, id in ipairs(ids) do
    cycle = _dagSort(out, id, parentMap, visited)
    if cycle then return nil, cycle end
  end
  return out
end

---------------------
-- BiMap

--- Bidirectional Map.
--- Maps both [$key -> value] and [$value -> key].
--- Must use [$:remove] (instead of [$bm[k] = nil] to handle deletions.
---
--- Note that [$pairs()] will return BOTH directions (in an unspecified order)
M.BiMap = mty'BiMap'{}
M.BiMap.__fields   = nil
M.BiMap.__fmt      = nil
M.BiMap.__tostring = nil

getmt(M.BiMap).__call = function(ty_, t)
  local rev = {}; for k, v in pairs(t) do rev[v] = k end
  for k, v in pairs(rev) do t[k] = v end
  return setmetatable(t, ty_)
end
M.BiMap.__newindex = function(t, k, v)
  rawset(t, k, v); rawset(t, v, k)
end
getmt(M.BiMap).__index = nil
M.BiMap.remove = function(t, k) --> v
  local v = t[k]; t[k] = nil; t[v] = nil; return v
end

---------------------
-- Deq Buffer

--- [$Deq() -> Deq], a deque
--- Use as a first in/out with [$deq:push(v)/deq()]
---
--- Main methods: [##
---   pushLeft()  pushRight()
---   popLeft()   popRight()
--- ]##
--- Calling it is the same as popLeft (use as iterator)
M.Deq = mty'Deq'{
  'right [number]',
  'left  [number]'
}
getmt(M.Deq).__call = function(T)
  return mty.construct(T, {right=0, left=1})
end
M.Deq.pushRight = function(deq, val)
  local r = deq.right + 1; deq[r] = val; deq.right = r
end
--- extend deq to right
M.Deq.extendRight = function(deq, vals) --> nil
  local r, vlen = deq.right, #vals
  move(vals, 1, vlen, r + 1, deq)
  deq.right = deq.right + vlen
end
M.Deq.pushLeft = function(deq, val) --> nil
  local l = deq.left - 1;  deq[l] = val; deq.left = l
end
--- extend deq to left ([$vals[1]] is left-most)
M.Deq.extendLeft = function(deq, vals) --> nil
  local vlen = #vals
  deq.left = deq.left - vlen
  move(vals, 1, vlen, deq.left, deq)
end
M.Deq.popLeft = function(deq) --> v
  local l = deq.left; if l > deq.right then return nil end
  local val = deq[l]; deq[l] = nil; deq.left = l + 1
  return val
end
M.Deq.popRight = function(deq) --> v
  local r = deq.right; if deq.left > r then return nil end
  local val = deq[r]; deq[r] = nil; deq.right = r - 1
  return val
end
M.Deq.push = M.Deq.pushRight --(d, v) --> nil
M.Deq.__len = function(d) return d.right - d.left + 1 end --> #d
M.Deq.pop = M.Deq.popLeft --> (d) -> v
M.Deq.__call = M.Deq.pop  --> () -> v
M.Deq.clear = function(deq) --> nil: clear deq
  local l = deq.left; move(EMPTY, l, deq.right, l, deq)
  deq.left, deq.right = 1, 0
end
M.Deq.drain = function(deq) --> table: get all items and clear deq
  local t = move(deq, deq.left, deq.right, 1, {})
  deq:clear(); return t
end

---------------------
-- TWriter: table writer
-- This is a table pretending to be a write-only file.

M.TWriter = mty'TWriter' {}
M.TWriter.write = function(tw, ...)
  push(tw, sconcat('', ...))
  return tw
end
M.TWriter.flush = M.noop
M.TWriter.close = M.noop

------------------
-- Export bytearray

if not G.NOLIB then
--- bytearray: an array of bytes that can also be used as a file.
---
--- Construct with [$bytearray(str...)]
---
--- Methods:[+
--- * [$b:len(v, fill='') --> int]
---     get (no args) or set the bytearray length. When v is set, the first
---     character of fill will be used to fill any characters above the current
---     length.
---
--- * [$b:size() --> int]
---     return the allocated space of the buffer.
---
--- * [$b:extend(str...) --> b]
---     extend bytearray with strings after len.
---
--- * [$b:sub(si, ei) --> string]: same as string:sub(...)
---
--- * [$b:replace(i, str)]:
---     replace the string at i with str, increasing length if necessary.
--- ]
---
--- In addition, bytearray is file-like with the methods read(), write(),
--- seek() and flush(). close() will free all internal memory. pos(n) gets and
--- sets the current "file" position, and supports negative indexes.
M.bytearray = lib.bytearray
M.bytearray.lines = function(b, opt)
  return function() return b:read(opt) end
end
M.bytearray.seek = function(b, whence, offset)
  if not whence or whence == 'cur' then return b:pos()
  elseif whence == 'set'           then return b:pos(offset or 0)
  elseif whence == 'end'           then return b:pos(-1) end
  error('unknown whence: '..whence)
end
M.bytearray.flush   = M.noop
M.bytearray.setvbuf = M.noop
end -- if not NOLIB

-----------------------
-- Handling Errors

--- Throw an error if [$select(i, ...)] is truthy, else return ...
---
--- For example, [$file:read'L'] returns [$line?, errmsg?].
--- However, the absence of line doesn't necessarily
--- indicate the presence of errmsg: EOF is just [$nil].
---
--- Therefore you can use [$line = check(2, f:read'L')]
--- to only assert on the presence of errmsg.
M.check = function(i, ...) --!> ...
  if select(i, ...) then error(tostring(select(i, ...))) end
  return ...
end

M.IGNORE_TRACE = {
  [""]=true,
  ['stack traceback:']=true,
  ["[C]: in function 'error'"]=true,
  ["[C]: in ?"]=true,
}
--- convert the string traceback into a list
M.tracelist = function(tbstr, level) --> {traceback}
  tbstr = tbstr or traceback(2 + (level or 0))
  local ig, tb = M.IGNORE_TRACE, {}
  for l in tbstr:gmatch'%s*([^\n]*)' do
    if not ig[l] then push(tb, l) end
  end
  return tb
end
M.traceback = function(level) --> string
  return concat(M.tracelist(nil, 1 + (level or 0)), '\n    ')
end

--- Error message, traceback and cause
--- NOTE: you should only use this for printing/logging/etc.
M.Error = mty'Error' {
  'msg [string]', 'traceback [table]', 'cause [Error]',
}
M.Error.__fmt = function(e, f)
  f:write('ERROR: ', e.msg)
  if e.traceback then
    f:write'\ntraceback:\n'
    for _, l in ipairs(e.traceback) do
      f:write('  ', l, '\n')
    end
  end
  if e.cause then
    f:write'\nCaused by: '
    f(e.cause); f:write'\n'
  end
end
M.Error.__tostring = function(e) return fmt(e) end

--- create the error from the arguments.
--- tb can be one of: [$coroutine|string|table]
M.Error.from = function(msg, tb, cause) --> Error
  tb = (type(tb) == 'thread') and traceback(tb) or tb
  return M.Error{
    msg=msg:match'^%S+/%S+:%d+: (.*)' or msg, -- remove line number
    traceback=(type(tb) == 'table') and tb or M.tracelist(tb),
    cause=cause,
  }
end

--- for use with xpcall. See: try
M.Error.msgh = function(msg, level) --> Error
  return M.Error.from(msg, traceback('', (level or 1) + 1))
end

--- try to run the fn. Similar to pcall. Return one of: [+
--- * successs: [$(true, ...)]
--- * failure: [$(false, ds.Error{...})]
--- ]
M.try = function(fn, ...) --> (ok, ...)
  return xpcall(fn, M.Error.msgh, ...)
end

--- Same as coroutine.resume except uses a ds.Error object for errors
--- (has traceback)
M.resume = function(th) --> (ok, err, b, c)
  local ok, a, b, c = resume(th)
  if ok then return ok, a, b, c end
  return nil, M.Error.from(a, th)
end

-----------------------
-- Import helpers

--- auto-set nil locals using require(mod)
--- [$local x, y, z; ds.auto'mm' -- sets x=mm.x; y=mm.y; z=mm.z]
M.auto = function(mod, i) --> (mod, i)
  mod, i = type(mod) == 'string' and require(mod) or mod, i or 1
  while true do
    local n, v = debug.getlocal(2, i)
    if not n then break end
    if nil == v then
      if not mod[n] then error(n.." not in module", 2) end
      debug.setlocal(2, i, mod[n])
    end
    i = i + 1
  end
  return mod, i
end

--- like require but returns nil
M.want = function(mod) --> module?
  local ok, m = pcall(function() return require(mod) end)
  if ok then return m end
end

--- indexrequire: [$R.foo] is same as [$require'foo']
--- This is mostly used in scripts/etc
M.R = setmetatable({}, {
  __index=function(_, k) return require(k) end,
  __newindex=function() error"don't set fields" end,
})

--- Include a resource (raw data) relative to the current file.
---
--- Example: [$M.myData = ds.resource'data/myData.csv']
M.resource = function(relpath)
  return require'ds.path'.read(M.srcdir(1)..relpath)
end

--- exit immediately with message and errorcode = 99
M.yeet = function(fmt, ...)
  io.fmt:styled('error',
    sfmt('YEET %s: %s', M.shortloc(1), sfmt(fmt or '', ...)),
    '\n')
  os.exit(99)
end

--- Print to io.sderr
M.eprint = function(...)
  local t = {...}; for i,v in ipairs(t)
    do t[i] = tostring(v)
  end
  io.stderr:write(concat(t, '\t'), '\n')
end

return M
