-- ds: data structures and algorithms

local M = mod and mod'ds' or {}

local mty = require'metaty'
local push, pop, sfmt    = table.insert, table.remove, string.format
local move, sort, unpack = table.move, table.sort, table.unpack
local ulen, uoff     = utf8.len, utf8.offset
local max = math.max
local xpcall, traceback = xpcall, debug.traceback
local resume = coroutine.resume
local str = mty.tostring
local EMPTY = {}

------------------
-- DS psudo-metaevents
-- these use new "metaevent" (similar to __len) that tables can override

-- if t is a table returns t.__name or '?'
M.name = function(t)
  if not type(t) == 'table' then return end
  local mt = getmetatable(t)
end


-- insert values into list at i.
-- Uses __inset "metamethod" if available.
-- rmlen, if provided, will cause t[i:i+rmlen] to be removed
M.inset = function(t, i, values, rmlen)
  local meth = mty.getmethod(t, '__inset')
  if meth then return meth(t, i, values, rmlen) end
  -- impl notes, there are two modes:
  -- * we want to keep some values after i: we cache those values then shift in
  -- * we don't want to keep values after i: we shift in the values and clear
  --   the rest
  rmlen = rmlen or 0; local tlen, vlen = #t, #values
  if tlen - i - rmlen >= 0 then -- we want to keep some values >= i
    local cache = move(t, i + rmlen, tlen, 1, {})
    move(values, 1, max(vlen, tlen - i + 1), i, t)
    move(cache, 1, #cache, i + vlen, t)
    return t
  end
  -- not keeping values >= i
  return move(values, 1, max(vlen, rmlen), max(1, i + 1 - rmlen), t)
end

---------------------
-- Pseudo Types
local CONCRETE_TYPES = {
  ['nil']=true, boolean=true, number=true, string=true
}

-- return true if the value is "plain old data".
--
-- Plain old data is defined as any concrete type or a table with no metatable
-- and who's pairs() are only POD.
local isPod; isPod = function(v)
  local ty = type(v)
  if ty == 'table' then
    local mt = getmetatable(v)
    if mt and (mt ~= 'table') then return false end
    for k, v in pairs(v) do
      if not (isPod(k) and isPod(v)) then
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

M.srcloc = function(level) --> "/path/to/dir/file.lua:10"
  local tb  = debug.traceback(nil, 2 + (level or 0))
  return assert(tb:match'.*traceback:%s+([^\n]+:%d+)')
end
M.shortloc = function(level) --> "dir/file.lua:10"
  local tb  = debug.traceback(nil, 2 + (level or 0))
  return assert(tb:match'.*traceback:%s+[^\n]-([^\n/]*/[^/\n]+:%d+)')
end
M.srcdir = function(level) --> "/path/to/dir/"
  return M.srcloc(1 + (level or 0)):match'^(.*/)[^/]+$'
end

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

M.brief = function(s, maxlen, trunc) --> string | str...
  maxlen, trunc = maxlen or 50, trunc or '...'
  if type(s) ~= 'string' then s = str(s) end
  return (#s <= maxlen) and s or (s:sub(1,maxlen)..trunc)
end

M.trim = function(subj, pat, index)
  pat = pat and ('^'..pat..'*(.-)'..pat..'*$') or '^%s*(.-)%s*$'
  return subj:match(pat, index)
end

--- return the first i characters and the remainder
M.strDivide = function(s, i)
  return s:sub(1, i), s:sub(i+1)
end

-- insert the value string at index
M.strInsert = function (s, i, v)
  return s:sub(1, i-1) .. v .. s:sub(i)
end

M.matches = function(s, m)
  local out = {}; for v in string.gmatch(s, m) do
    push(out, v) end
  return out
end

-- split strings
M.split = mty.split
M.splitList = function(...)
  local t = {}; for _, v in mty.split(...) do push(t, v) end
  return t
end
M.explode = function(s) return M.matches(s, '.') end
M.concatToStrs = function(t, sep)
  local o = {}; for _, v in ipairs(t) do push(o, str(v)) end
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

-- trim the end of the string by removing pat (default='%s')
M.trimEnd = function(subj, pat, index)
  pat = pat and ('^(.-)'..pat..'*$') or '^(.-)%s*$'
  return subj:match(pat, index)
end

-- Squash a string: convert all whitespace to repl (default=' ').
M.squash = function(s, repl) return s:gsub('%s+', repl or ' ') end

-- utf8 sub. If len is pre-computed you can pass it in for better performance.
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

--------------------
-- Working with file paths

-- get current working directory
M.cwd = function() return CWD or os.getenv'PWD' or os.getenv'CD' end

M.home = function() return HOME or os.getenv'HOME'
                        or os.getenv'HOMEDIR'      end

-- submodule for paths.
-- Call directly to convert a list|str to a list of path components.
M.path = mod and mod'ds.path' or setmetatable({}, {})
getmetatable(M.path).__call = function(_, p)
  if type(p) == 'table' then return p end
  p = M.splitList(p, '/+')
  if p[1] == ''  then p[1] = '/' end
  local len = #p
  if len > 1 and p[len] == '' then
    p[len - 1] = p[len - 1]..'/'; p[len] = nil
  end
  return p
end

-- join a table of path components
M.path.concat = function(t)
  if #t == 0 then return '' end
  local root = (t[1]:sub(1,1)=='/') and '/' or ''
  local dir  = (t[#t]:sub(-1)=='/') and '/' or ''
  local out = {}
  for i, p in ipairs(t) do
    p = string.match(p, '^/*(.-)/*$')
    if p ~= '' then push(out, p) end
  end; return root..table.concat(out, '/')..dir
end


-- return whether a path has any '..' components
M.path.hasBacktrack = function(path) --> bool. path: [str|list]
  if type(path) == 'string' then
    return path:match'^%.%.$' or path:match'^%.%./'
        or path:match'/%.%./' or path:match'/%.%.$'
  end
  for _, c in ipairs(path) do
    if c == '..' then return true end
  end; return false
end
M.path.ext = function(path) --> boolean. path: [str|list]
  if type(path) == 'table' then path = path[#path] end
  return path:match'.*%.([^/]+)$'
end

-- Ensure the path is absolute, using the wd (default=cwd()) if necessary
M.path.abs = function(path, wd) --> /absolute/path
  if type(path) == 'string' then
    if (path:sub(1,1) == '/') then return path end
    wd = wd or M.cwd()
    return (wd:sub(-1) == '/') and (wd..path)
                               or  (wd..'/'..path)
  end
  if path[1]:sub(1,1) == '/' then return path end
  assert(type(wd) == 'string')
  return M.extend(M.path(wd), path)
end

local DOTS = {['.']=true, ['..']=true}
-- resolve any `..` or `.` path components, making the path
-- absolute if necessary.
M.path.resolve = function(path, wd) --> list
  if type(path) == 'table' then path = ds.copy(path)
  else path = M.path(path) end

  -- walk path, resolving . and ..
  local i, j, len = 1, 1, #path
  local isdir = path[len]:sub(-1) == '/' or DOTS[path[len]]
  while j <= len do
    local c = path[j]
    if c == '.' then j = j + 1 -- skip
    elseif c == '..' then      -- backtrack
      i = i - 1; j = j + 1
      if i < 1 then
        assert(path[1] ~= '/', 'backtracks are before root')
        local abs = M.path(wd or M.cwd())
        len = #abs
        table.move(path, j, #path + 1, len, abs)
        i, j      = len, len
        path, len = abs, #abs
      end
    else
      path[i] = path[j]
      i = i + 1; j = j + 1
    end
  end
  M.clear(path, i, len)
  local last = path[#path]
  if isdir and last:sub(-1) ~= '/' then
    path[#path] = last..'/'
  end
  return path
end

-- first/middle/last -> ("first", "middle/last")
M.path.first = function(path)
  if path:sub(1,1) == '/' then return '/', path:sub(2) end
  local a, b = path:match('^(.-)/(.*)$')
  if not a or a == '' or b == '' then return path, '' end
  return a, b
end

-- first/middle/last -> ("first/middle", "last")
M.path.last = function(path)
  local a, b = path:match('^(.*)/(.+)$')
  if not a or a == '' or b == '' then return '', path end
  return a, b
end

---------------------
-- Table Functions

M.isEmpty = function(t) return next(t) == nil end

-- sort table and return it.
-- Eventually this may use the __sort metamethod
M.sort = function(t, fn) sort(t, fn); return t end --> t

-- get index, handling negatives
M.geti = function(t, i)
  return (i >= 0) and t[i] or t[#t + i + 1]
end
M.last = function(t) return t[#t] end

-- get the first and only element of the list
M.only = function(t)
  mty.assertf(#t == 1, 'len ~= 1: %s', #t)
  return t[1]
end

-- get only the values of pairs(t) as a list
M.values = function(t)
  local vals = {}; for _, v in pairs(t) do push(vals, v) end
  return vals
end

-- get only the keys of pairs(t) as a list
M.keys = function(t)
  local keys = {}; for k in pairs(t) do push(keys, k) end
  return keys
end

M.inext = ipairs{} -- next(t, key) but with indexes

-- inext but reversed.
M.iprev = function(t, i)
  if i > 1 then return i - 1, t[i - 1] end
end

-- ipairs reversed
M.ireverse = function(t) return M.iprev, t, #t + 1 end

-- for i, v in rawislice({t, endi}, starti)
M.rawislice = function(state, i)
  i = i + 1; if i > state[2] then return end
  return i, state[1][i]
end

-- islice(t, starti, endi=#t): iterate over slice.
--   Unlike other i* functions, this ignores length
--   except as the default value of endi
M.islice = function(t, starti, endi)
  return M.rawislice, {t, endi or #t}, (starti or 1) - 1
end

-- iend(t, starti, endi=-1): get islice from the end.
--   starti and endi must be negative.
-- 
-- Example:
--   iend({1, 2, 3, 4, 5}, -3, -2) -> 3, 4
M.ilast = function(t, starti, endi)
  local len = #t; endi = endi and math.min(len, len + endi + 1) or len
  return M.rawislice, {t, endi}, math.min(len - 1, len + starti)
end

-- convert (_, v) iterator into a table by pushing
M.itable = function(it)
  local o = {}; for _, v in unpack(it) do push(o, v) end;
  return o
end

-- convert (k, v) iterator into a table by setting
M.kvtable = (function(it)
  local o = {}; for k, v in unpack(it) do o[k] = v end;
  return o
end)

-- reverse a list-like table in-place
M.reverse = function(t)
  local l = #t; for i=1, l/2 do
    t[i], t[l-i+1] = t[l-i+1], t[i]
  end
  return t
end

-- extend(t, list) -> t: move vals to the end of t
M.extend = function(t, l) return move(l, 1, #l, #t + 1, t) end
-- clear(t, startindex=1, len=#t) -> t: set t[si:si+len-1] = nil
M.clear  = function(t, si, len)
  -- TODO: (len or #t) - si + 1
  return move(EMPTY, 1, len or #t, si or 1, t)
end
-- append one or more values to t
M.add = function(t, ...) --> t
  local tend = #t
  for i=1,select('#', ...) do t[tend + i] = select(i, ...) end
  return t
end
-- replace(t, r): make t's index values the same as r's
M.replace = function(t, r)
  return move(r, 1, math.max(#t, #r), 1, t)
end
M.update = function(t, add)
  for k, v in pairs(add) do t[k] = v end; return t
end
M.updateKeys = function(t, add, keys)
  for _, k in ipairs(keys) do t[k] = add[k] end; return t
end
M.orderedKeys = function(t)
  local keys = {}; for k in pairs(t) do push(keys, k) end
  sort(keys)
  return keys
end
-- recursively update t with add. This will call update on inner tables as
-- well.
-- Note: treats list indexes as normal keys (does not append)
M.merge = function(t, add)
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

-- drain(t, len=#t) -> t[#t-len:#t]
-- return len items from the end of t, removing them from t.
M.drain = function(t, len)
  local out = {}; for i=1, math.min(#t, len) do push(out, pop(t)) end
  return M.reverse(out)
end

M.getOrSet = function(t, k, newFn)
  local v = t[k]; if v ~= nil then return v end
  v = newFn(t, k); t[k] = v
  return v
end

M.setIfNil = function(t, k, v)
  if t[k] == nil then t[k] = v end
end
M.emptyTable = function() return {} end

-- used with ds.get and ds.set
-- Example:
--   local dp = require'ds'.dotpath
--   ds.get(t, dp'a.b.c')
M.dotpath = function(dots) --> list split by '.'
  local p = {}; for v in dots:gmatch'[^%.]+' do push(p, v) end
  return p
end

-- get the value at the path or nil if the value or any
-- intermediate table is missing.
-- [##
--   get(t, {'a', 2, 'c'})  -> t.a?[2]?.c?
--   get(t, dotpath'a.b.c') -> t.a?.b?.c?
-- ]##
M.get = function(t, path) --> value? at path
  for _, k in ipairs(path) do
    t = t[k]; if t == nil then return nil end
  end
  return t
end

-- set the value at path using newFn (default=ds.newTable) to create
-- missing intermediate tables.
-- [##
--   set(t, dotpath'a.b.c', 2) -> t.a?.b?.c = 2
-- ]##
M.set = function(d, path, value, newFn)
  newFn = newFn or M.emptyTable
  local len = #path; assert(len > 0, 'empty path')
  for i=1,len-1 do d = M.getOrSet(d, path[i], newFn) end
  d[path[len]] = value
end

M.indexOf = function(t, find)
  for i, v in ipairs(t) do
    if v == find then return i end
  end
end

M.indexOfPat = function(strs, pat)
  for i, s in ipairs(strs) do if s:find(pat) then return i end end
end

-- popit(t, i) -> t[i]  -- also, the length of t is reduced by 1
-- 
-- popit (aka pop-index-top) will return the value at t[i], replacing it with the
-- value at the end (aka top) of the list.
-- 
-- if i > #t returns nil and doesn't affect the size of the list.
M.popit = function(t, i)
  local len = #t; if i > len then return end
  local o = t[i]; t[i] = t[len]; t[len] = nil
  return o
end

-- walk(tbl, fieldFn, tableFn, maxDepth, state)
-- Walk the table up to depth maxDepth (or infinite if nil).
-- 
-- fieldFn(key, value, state)  -> stop  is called for every non-table value.
-- tableFn(key, tblValue, state) -> stop is called for every table value
-- 
-- If tableFn stop==ds.SKIP (i.e. 'skip') then that table is not recursed.
-- Else if stop then the walk is halted immediately
M.walk = function(t, fieldFn, tableFn, maxDepth, state)
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
M.readPath = function(path)
  local f = mty.assertf(io.open(path), 'invalid %s', path)
  local out = f:read('a'); f:close()
  return out
end

M.writePath = function(path, text)
  local f = mty.assertf(io.open(path, 'w'), 'invalid %s', path)
  local out = f:write(text); f:close()
  return out
end

M.fileWithText = function(path, text, mode)
  local f = mty.assertf(
    io.open(path, mode or 'w+'), 'invalid %s', path)
  f:write(text); f:flush(); f:seek'set'
  return f
end

-- fdMv(fdTo, fdFrom): memonic fdTo = fdFrom
-- Read data from fdFrom and write to fdTo, then flush.
M.fdMv = function(fdTo, fdFrom)
  while true do
    local d = fdFrom:read(4096); if not d then break end
    fdTo:write(d)
  end fdTo:flush()
  return fdTo, fdFrom
end

---------------------
-- Source Code Functions

-- convert lines-like table into chunk for eval
M.lineschunk =
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

-- Weak key table, see docs on '__mode'
M.WeakK = setmetatable(
  {__name='WeakK', __mode='k'}, {
  __name='Ty<WeakK>', __call=mty.constructUnchecked,
})

-- Weak value table, see docs on '__mode'
M.WeakV = setmetatable(
  {__name='WeakV', __mode='v'}, {
  __name='Ty<WeakV>', __call=mty.constructUnchecked,
})

-- Weak key+value table, see docs on '__mode'
M.WeakKV = setmetatable(
  {__name='WeakKV', __mode='kv'}, {
  __name='Ty<WeakKV>', __call=mty.constructUnchecked,
})

-- Table that never accepts new indexes. Used to disable caching in tests.
M.Forget = setmetatable(
  {__name='Loser', __newindex=M.noop},
  {__name='Ty<Loser>', __call=mty.constructUnchecked}
)

-- Table that errors on missing key
M.Checked = setmetatable(
  {__name='Checked', __metatable='table',
   __index=function(_, k) error('unknown key: '..k) end,
  },
  {__name='Ty<Checked>', __call=mty.constructUnchecked}
)

---------------------
-- Sentinal, none type, bool()

local _si=function() error('invalid operation on sentinel', 2) end
-- sentinel(name, metatable)
-- Use to create a "sentinel type". Return the (singular) instance.
--
-- Sentinels are "single values" commonly used for things like: none, empty, EOF, etc.
-- They have most metatable methods disallowed and are immutable down. Methods can
-- only be set by the provided metatable value.
M.sentinel = function(name, mt)
  mt = M.update({
    __name=name, __tostring=function() return name end,
    __newindex=_si, __len=_si, __pairs=_si,
  }, mt or {})
  mt.__index = mt
  setmetatable(mt, {__name='Ty<'..name..'>', __index=mty.indexError})
  return setmetatable({}, mt)
end

-- none: "set as none" vs nil aka "unset"
--
-- none is a sentinel value. Use it in APIs where there is an
-- "unset but none" such as JSON's "null".
M.none = M.sentinel('none', {__metatable='none'})

-- convert to boolean (none aware)
M.bool =
(function(v) return not rawequal(M.none, v) and v and true or false end)

-- An immutable empty table
M.empty = setmetatable({}, {
  __newindex = function() error('mutate ds.empty', 2) end,
  __metatable = 'table',
})

-- Immutable table
M.Imm = mty'Imm' {}
local IMM_DATA = '<!imm data!>'
getmetatable(M.Imm).__call = function(T, t)
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
getmetatable(M.Duration).__call = timeNew

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
getmetatable(M.Epoch).__call = timeNew

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
getmetatable(M.Set).__index = nil
getmetatable(M.Set).__call = function(T, t)
  local s = {}
  for _, k in ipairs(t) do s[k] = true end
  return mty.constructUnchecked(T, s)
end

M.Set.__fmt = function(self, f)
  push(f, 'Set'); push(f, f.tableStart);
  local keys = {}; for k in ipairs(self) do push(keys, k) end
  sort(keys)
  if #keys > 1 then f:incIndent() end
  for i, k in ipairs(keys) do
    f:fmt(k)
    if i < #keys then push(f, f.indexEnd) end
  end
  if #keys > 1 then f:decIndent() end
  push(f, f.tableEnd)
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

-- Tiny linked-list module.
--   This uses indexes to track linked-lists, making it
--   extremely memory efficient and fairly performant.
-- 
-- -- 1 [-> ...]            linked list with just root
-- local llp, lln, llv = {0}, {0}, {}
-- 
-- -- 1 -> 2 [-> 1...]      append 2 to root
-- ll.push(llp, lln, 1, 2); llv[2] = 'value@2'
-- 
-- -- 3 -> 1 -> 2 [-> 3...] prepend 3 to root
-- ll.budge(llp, lln, 1, 3); llv[3] = 'value@3'
-- 
-- -- 3 -> 1 [-> 3...]      pop 2
-- ll.pop(llp, lln, 2)
M.ll = mod and mod'll' or {}

-- get initial llp, lln, llv
M.ll.empty = function() return {1}, {1}, {} end

-- a -> node -> b  ==> a -> b
M.ll.pop = function(prev, nxt, node)
  local a, b = prev[node], nxt[node]
  nxt[a], prev[b] = b, a
end

-- node -> b  ==>  node -> a -> b
M.ll.push = function(prev, nxt, node, a)
  local b = nxt[node]
  nxt[node],  nxt[a]  = assert(a), b
  prev[b],    prev[a] = a, node
end

-- b -> node ==>  b -> a -> node
M.ll.budge = function(prev, nxt, node, a)
  local b = prev[node]
  nxt[b],     nxt[a]  = a, node
  prev[node], prev[a] = a, b
end

M.LL = mty'LL' {
  'front[&table]', 'back[&table]',
}

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

-- binarySearch(t, v, cmp, si, ei) -> i
--   cmp = ds.lte by default
--   si = start index, default=1
--   ei = end index,   default=#t
-- 
-- Search the sorted table, return i such that:
-- * cmp(t[i], v) returns true  for indexes <= i
-- * cmp(t[i], v) returns false for indexes >  i
-- 
-- If you want a value perfectly equal then check equality
-- on the resulting index.
M.binarySearch = function(t, v, cmp, si, ei)
  return _bs(t, v, cmp or M.lte, si or 1, ei or #t)
end

---------------------
-- Binary Tree

-- ds.bt: indexed table as Binary Tree.
-- These functions treat an indexed table as a binary tree
-- where root is at index=1.
M.bt = mod and mod'bt' or {}
M.bt.left = function(t, i)    return t[i * 2]     end
M.bt.right = function(t, i)   return t[i * 2 + 1] end
M.bt.parent = function(t, i)  return t[i // 2]    end
M.bt.lefti = function(t, i)   return   i * 2      end
M.bt.righti = function(t, i)  return   i * 2 + 1  end
M.bt.parenti = function(t, i) return   i // 2     end

---------------------
-- Directed Acyclic Graph

-- Functions for working with directed acyclic graphs.
M.dag = mod and mod'dag' or {}

local function _dagSort(st, name, parents)
  if st.visited[name] then return end; st.visited[name] = true
  if parents then for _, pname in ipairs(parents) do
    _dagSort(st, pname, st.depsMap[pname])
  end end
  push(st.out, name)
end

-- dag.sort(depsMap) -> sortedDeps
-- 
-- Sort the directed acyclic graph. depsMap must behave like a table which:
-- 
--   for pairs(depsMap) -> nodeName, ...
--   depsMap[nodeName]  -> nodeDeps (list)
-- 
-- If depsMap is a map of pkg -> depPkgs then the result is the order the pkgs
-- should be built.
-- 
-- Note: this function does NOT detect cycles.
M.dag.sort = function(depsMap)
  local state = {depsMap=depsMap, out={}, visited={}}
  for name, parents in pairs(depsMap) do
    _dagSort(state, name, parents)
  end
  return state.out
end

-- dag.reverseMap(childrenMap) -> parentsMap (or vice-versa)
M.dag.reverseMap = function(childrenMap)
  local pmap = {}
  for pname, children in pairs(childrenMap) do
    M.getOrSet(pmap, pname, M.emptyTable)
    if children then for _, cname in ipairs(children) do
      push(M.getOrSet(pmap, cname, M.emptyTable), pname)
    end end
  end
  return pmap
end

-- dag.missing(depsMap) -> missingDeps
-- 
-- Given a depsMap return missing deps (items in a deps with no name).
M.dag.missing = function(depsMap)
  local missing = {}; for n, deps in pairs(depsMap) do
    for _, dep in ipairs(deps) do
      if not depsMap[dep] then missing[dep] = true end
    end
  end
  return missing
end

---------------------
-- BiMap
-- BiMap{} -> biMap: Bidirectional Map
-- maps both key -> value and value -> key
-- must use `:remove` (instead of `bm[k] = nil` to handle deletions.
--
-- Note that pairs() will return BOTH directions (in an unspecified order)
M.BiMap = mty'BiMap'{}

getmetatable(M.BiMap).__call = function(ty_, t)
  local keys = {}; for k, v in pairs(t) do
    if not t[v] then push(keys, k) end
  end
  for _, k in pairs(keys) do t[t[k]] = k end
  return setmetatable(t, ty_)
end
M.BiMap.__fields = nil
M.BiMap.__newindex = function(t, k, v)
  rawset(t, k, v); rawset(t, v, k)
end
getmetatable(M.BiMap).__index = nil
M.BiMap.__fmt = nil
M.BiMap.remove = function(t, k)
  local v = t[k]; t[k] = nil; t[v] = nil
end

---------------------
-- Deq Buffer
-- Deq() -> Deq, a deque
-- Use as a first in/out with deq:push(v)/deq()
--
-- Main methods:
--   pushLeft()  pushRight()
--   popLeft()   popRight()
--
-- Calling it is the same as popLeft (use as iterator)
M.Deq = mty'Deq'{
  'right [number]',
  'left  [number]'
}
getmetatable(M.Deq).__call = function(T)
  return mty.construct(T, {right=0, left=1})
end
M.Deq.pushRight = function(deq, val)
  local r = deq.right + 1; deq[r] = val; deq.right = r
end
-- extend deq to right
M.Deq.extendRight = function(deq, vals)
  local r, vlen = deq.right, #vals
  move(vals, 1, vlen, r + 1, deq)
  deq.right = deq.right + vlen
end
M.Deq.pushLeft = function(deq, val)
  local l = deq.left - 1;  deq[l] = val; deq.left = l
end
-- extend deq to left (vals[1] is left-most)
M.Deq.extendLeft = function(deq, vals)
  local vlen = #vals
  deq.left = deq.left - vlen
  move(vals, 1, vlen, deq.left, deq)
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
M.Deq.clear = function(deq) -- clear deq
  local l = deq.left; move(EMPTY, l, deq.right, l, deq)
  deq.left, deq.right = 1, 0
end
M.Deq.drain = function(deq) --> table: get all items and clear deq
  local t = move(deq, deq.left, deq.right, 1, {})
  deq:clear(); return t
end

-----------------------
-- ERROR type

M.IGNORE_TRACE = {
  [""]=true,
  ['stack traceback:']=true,
  ["[C]: in function 'error'"]=true,
  ["[C]: in ?"]=true,
}
-- convert the string traceback into a list
M.tracelist = function(tbstr) --> {traceback}
  local ig, tb = M.IGNORE_TRACE, {}
  for l in tbstr:gmatch'%s*([^\n]*)' do
    if not ig[l] then push(tb, l) end
  end
  return tb
end

-- Error message, traceback and cause
-- NOTE: you should only use this for printing/logging/etc.
M.Error = mty'Error' {
  'msg [string]', 'traceback [table]', 'cause [Error]',
}
M.Error.__fmt = function(e, fmt)
  push(fmt, 'ERROR: '); push(fmt, e.msg)
  if e.traceback then
    push(fmt, '\ntraceback:\n')
    for _, l in ipairs(e.traceback) do
      push(fmt, '  '); push(fmt, l); push(fmt, '\n')
    end
  end
  if e.cause then
    push(fmt, '\nCaused by: ');
    fmt(e.cause); push(fmt, '\n')
  end
end
M.Error.__tostring = function(e) return str(e) end

-- create the error from the arguments.
-- tb can be one of: coroutine|string|table
M.Error.from = function(msg, tb, cause)
  tb = (type(tb) == 'thread') and traceback(tb) or tb
  return M.Error{
    msg=msg:match'^%S+/%S+:%d+: (.*)' or msg, -- remove line number
    traceback=(type(tb) == 'table') and tb or M.tracelist(tb),
    cause=cause,
  }
end

-- for use with xpcall. See: try
M.Error.msgh = function(msg, level)
  return M.Error.from(msg, traceback('', (level or 1) + 1))
end

-- Run the fn, return one of:
-- success(true, fnresults...); failure(false, ds.Error)
M.try = function(fn, ...) return xpcall(fn, M.Error.msgh, ...) end

-- Same as coroutine.resume except returns ok, err
-- where Err is an ds.Error object (has traceback)
--
-- Only returns up to 4 items
M.resume = function(th) --> ok, err|...
  local ok, a, b, c = resume(th)
  if ok then return ok, a, b, c end
  return nil, M.Error.from(a, th)
end

-----------------------
-- Import helpers

-- auto-set nil locals using require(mod)
-- local x, y, z; ds.auto'mm' -- sets x=mm.x; y=mm.y; z=mm.z
M.auto = function(mod, i)
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

-- indexrequire: `R.foo` is same as `require'foo'`
-- This is mostly used in scripts/etc
M.R = setmetatable({}, {
  __index=function(_, k) return require(k) end,
  __newindex=function() error"don't set fields" end,
})

-- Include a resource (raw data) relative to the current file.
--
-- Example:
--   M.myData = ds.resource'data/myData.csv'
M.resource = function(relpath)
  assert(not relpath:match'%.%./', 'previous path ".." not allowed')
  return M.readPath(M.srcdir(1)..relpath)
end

return M
