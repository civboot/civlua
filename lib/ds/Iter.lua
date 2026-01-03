local mty = require'metaty'
--- Fluent iterator
---
--- [{## lang=lua}
--- isNumber = function(v) return type(v) == 'number' end
--- t = {4, 5, 'six', 7}
--- T.eq(
---   {'4', '5', '7'},
---   Iter:ofList(t)       -- iterate over ipairs(t)
---     :filterV(isNumber) -- only numbers
---     :mapV(tostring)    -- convert to string
---     :valsTo())         -- collect list of values (drops keys)
--- ]##
local Iter = mty'Iter' {
  '_li [int]: left index of fns (stored at negative index)', _li = 0,
  '_nextK [any]: next key when [$iter()]ated',
}

local ds = require'ds'
local fmt = require'fmt'

local select, unpack = select, table.unpack
local pairs, ipairs = pairs, ipairs
local push, sort = table.insert, table.sort
local concat = table.concat
local construct = mty.construct
local rawislice, inext = ds.rawislice, ds.inext

local swapKV = function(k, v) return v, k end

--------------------------------
-- Constructors

--- construct from table of [${nextFn, state, startK}] (see [$help 'for']).
--- Examples: [{## lang=lua}
---   it = Iter{pairs(t)}  -- recommendation: use It:of(t) instead
---   it = Iter{ipairs(t)} -- recommendation: use It:ofList(t) instead
---   it = Iter{myIterFn}
--- ]##
getmetatable(Iter).__call = function(T, t)
  t._nextK = t[3]; return setmetatable(t, T)
end

--- create iterable of [$pairs(t)]
Iter.of = function(T, t) return T{pairs(t)} end

--- create iterable of [$ipairs(t)]
Iter.ofList = function(T, t) return T{ipairs(t)} end

--- create an iterable that returns [$table.unpack] on each
--- value in [$ipairs(t)].
---
--- i.e. [$Iter:ofUnpacked{{5, 'five'}, {6, 'six'}}] will
--- return (5, 'five') then (6, 'six')
Iter.ofUnpacked = function(T, t)
  local i, len = 0, #t
  return T{function()
    if i >= len then return end
    i = i + 1; return unpack(t[i])
  end}
end

--- create an iterable of [$t] which emits keys in order.
--- [" WARNING: this first sorts the keys, which can be slow]
Iter.ofOrdMap = function(T, t, cmpFn) --> sortedIter[k, v]
  local keys = {}; for k, v in pairs(t) do push(keys, k) end
  sort(keys, cmpFn)
  return T{pairs(keys)}:lookup(t)
end

--- sort t then iterate over list
Iter.ofOrdList = function(T, t, cmpFn) --> sortedIter[i, v]
  sort(t, cmpFn); return T{ipairs(t)}
end

--- iterate over slice of [$starti:endi] in [$t]
Iter.ofSlc = function(T, t, starti, endi) --> iter[i, v]
  if endi then
    return T{rawislice, {t, endi}, (starti or 1) - 1}
  end
  return T{inext, t, (starti or 1) - 1}
end

--------------------------------
-- Mapping methods

--- emit [$k, v = fn(v)] for each non-nil result
---
--- ["Note: if performance matters this is the most performant
---         application function since it doesn't create an internal
---         function.
--- ]
Iter.map = function(it, fn) --> it
  local li = it._li - 1; it[li] = fn; it._li = li
  return it
end

---- emit [$fn(k), v)] for each non-nil result.
Iter.mapK = function(it, fn) --> it
  return it:map(function(k, v) k = fn(k); return k, v end)
end

--- emit [$k, fn(v)] for each non-nil result.
--- (filtered when [$newK==nil])
Iter.mapV = function(it, fn) --> it
  return it:map(function(k, v)
    v = fn(v); if v ~= nil then return k, v end
  end)
end

---- emit only [$if fn(k, v)] results
Iter.filter = function(it, fn) --> it
  return it:map(function(k, v)
    local b = fn(k, v); if b then return k, v end
  end)
end

---- emit only [$if fn(k)] results
Iter.filterK = function(it, fn) --> it
  return it:map(function(k, v)
    local b = fn(k); if b then return k, v end
  end)
end

---- emit only [$if fn(v)] results
Iter.filterV = function(it, fn) --> it
  return it:map(function(k, v)
    local b = fn(v); if b then return k, v end
  end)
end


--- emit[$v, $t[k]], looking up the iter's values in the table's keys.
Iter.lookup = function(it, t) --> it
  return it:map(function(_, v) return v, t[v] end)
end

--- emit [$t[k], v] for each non-nil [$t[k]]
Iter.lookupK = function(it, t) --> it
  return it:map(function(k, v) return t[k], v end)
end

--- emit [$k, $t[v]] for each non-nil [$t[v]]
Iter.lookupV = function(it, t) --> it
  return it:map(function(k, v)
    v = t[v]; if v ~= nil then return k, v end
  end)
end

--- emit [$k, v] for each non-nil [$t[k]]
Iter.keyIn = function(it, t) --> it
  return it:map(function(k, v)
    if t[k] ~= nil then return k, v end
  end)
end

--- emit [$k, v] for each nil [$t[k]]
Iter.keyNotIn = function(it, t) --> it
  return it:map(function(k, v)
    if t[k] == nil then return k, v end
  end)
end

--- emit [$k, v] for each non-nil [$t[v]]
Iter.valIn = function(it, t) --> it
  return it:map(function(k, v)
    if t[v] ~= nil then return k, v end
  end)
end

--- emit [$k, v] for each nil [$t[v]]
Iter.valNotIn = function(it, t) --> it
  return it:map(function(k, v)
    if t[v] == nil then return k, v end
  end)
end

--- emit [$k, v] after calling [$fn(k, v)].
--- The results of the fn are ignored
Iter.listen = function(it, fn) --> it
  return it:map(function(k, v) fn(k, v); return k, v end)
end

--- emit [$i, k], dropping values. [$i] starts at [$1] and increments each
--- time called.
---
--- [" Note: this is most useful for iterators which don't emit a [$v].
---    i.e. getting the line number in [$file:lines()]]
Iter.index = function(it) --> it
  local i = 0; return it:map(function(_, v) i = i + 1; return i, v end)
end

--- emit [$v, k] (swaps key and value)
Iter.swap = function(it) --> it[v, k]
  return it:map(swapKV)
end

--------------------------------
-- Collecting Methods

--- run the iterator over all values, calling [$fn(k, v)] for each.
--- return the first [$k, v] where the fn returns a truthy value.
Iter.find = function(it, fn) --> k, v
  local li, k = it._li
  for key, v in unpack(it) do
    k = key; for i=-1,li,-1 do
      k, v = it[i](k, v); if k == nil then goto skip end
    end
    if fn(k, v) then return k, v end
    ::skip::
  end
end


local allFn = function(k, v) return not v end -- stop on first falsy
--- return true if any of the values are truthy
Iter.all = function(it) return not it:find(allFn) end

local anyFn = function(k, v) return v end     -- stop on first true
--- return true if any of the values are truthy
Iter.any = function(it) return not not it:find(anyFn) end

--- run the iterator over all values, calling [$fn(k, v)] for each.
Iter.run = function(it, fn--[[noop]]) --> nil
  local li, fn, k = it._li, fn or ds.noop
  for key, v in unpack(it) do
    k = key; for i=-1,li,-1 do
      k, v = it[i](k, v); if k == nil then goto skip end
    end
    fn(k, v)
    ::skip::
  end
end

--- collect non-nil [$k, v] into table-like object [$to]
Iter.to = function--(it, to={}) --> to
  (it, to) to = to or {}
  it:run(function(k, v) to[k] = v end)
  return to
end

--- collect emitted [$k] as a list (vals are dropped)
Iter.keysTo = function--(it, to={}) --> to
  (it, to) to = to or {}
  it:run(function(k) push(to, k) end)
  return to
end

--- collect emitted [$v] as a list (keys are dropped)
Iter.valsTo = function--(it, to={}) --> to
  (it, to) to = to or {}
  it:run(function(k, v) push(to, v) end)
  return to
end

Iter.concat = function(it, sep) return concat(it:to(), sep) end

--- reset the iterator to run from the start
Iter.reset = function(it) it._nextK = it[3]; return it end --> it

--- use as an iterator.
Iter.__call = function(it)
  local li, k = it._li
  for key, v in it[1], it[2], it._nextK do
    k, it._nextK = key, key
    for i=-1,li,-1 do
      k, v = it[i](k, v); if k == nil then goto skip end
    end
    do return k, v end -- `do` necessary for parser
    ::skip::
  end
end
Iter.__ipairs = ds.nosupport

--- create an iterator that returns a single value
Iter.single = function(k, v) --> fn(): (k, v) .. nil
  local done = false; return function()
    if not done then done = true; return k, v end
  end
end

--- Used for testing. [$Iter:assertEq(it1, it2)] constructs both
--- iterators using [$Iter()] and then asserts the results are
--- identical.
Iter.assertEq = function(it1, it2)
  assert(mty.ty(it1) == Iter, 'it1 is not Iter')
  assert(mty.ty(it2) == Iter, 'it2 is not Iter')
  local i, T = 0, require'civtest'
  while true do
    i = i + 1
    local r1 = {it1()}
    local r2 = {it2()}
    if not mty.eq(r1, r2) then
      io.fmt:styled('error', 'Result differs at index '..i, '\n')
      assertEq(r1, r2); error'unreachable'
    end
    if rawequal(r1[1], nil) then return end
  end
end

return Iter
