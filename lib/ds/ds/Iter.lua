local mty = require'metaty'
--- fluent iterator
---
--- [{## lang=lua}
--- isNumber = function(v) return type(v) == 'number' end
--- t = {4, 5, 'six', 7}
--- assertEq(
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

local select, unpack = select, table.unpack
local pairs, ipairs = pairs, ipairs
local push, sort = table.insert, table.sort
local construct = mty.construct
local rawislice, inext = ds.rawislice, ds.inext

local swapKV = function(k, v) return v, k end

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

--- create an iterable of [$t] which emits keys in order.
---
--- [" WARNING: this first sorts the keys, which can be slow]
Iter.ofOrdMap = function(T, t, cmpFn)
  local keys = {}; for k, v in pairs(t) do push(keys, k) end
  sort(keys, cmpFn)
  return T{pairs(keys)}:lookup(t)
end

--- sort t then iterate over list
Iter.ofOrdList = function(T, t, cmpFn)
  sort(t, cmpFn); return T{ipairs(t)}
end

--- iterate over slice of [$starti:endi] in [$t]
Iter.ofSlc = function(T, t, starti, endi)
  if endi then
    return T{rawislice, {t, endi}, (starti or 1) - 1}
  end
  return T{inext, t, (starti or 1) - 1}
end

--- emit [$k, fn(v)] for each non-nil result
---
--- ["Note: if performance matters this is the most performant
---         application function since it doesn't create an internal
---         function.
--- ]
Iter.map = function(it, fn)
  local li = it._li - 1; it[li] = fn; it._li = li
  return it
end

---- emit [$fn(k), v)] for each non-nil result.
Iter.mapK = function(it, fn) --> it
  return it:map(function(k, v) k = fn(k); return k, v end)
end

--- emit [$k, fn(v)] for each non-nil result.
--- (filtered when [$newK==nil])
Iter.mapV = function(it, fn)
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

--- emit [$i, k], dropping values. [$i] starts at [$1] and increments each
--- time called.
---
--- [" Note: this is most useful for iterators which don't emit a [$v].
---    i.e. getting the line number in [$file:lines()]]
Iter.index = function(it) --> it
  local i = 0; return it:map(function(_, v) i = i + 1; return i, v end)
end

--- emit [$v, k] (swaps key and value)
Iter.swap = function(it) return it:map(swapKV) end --> it

-----------------------
-- Collecting Methods

--- collect non-nil [$k, v] as a table.
Iter.to = function(it, to) --> to
  local li, to, k, v = it._li, to or {}
  for key, v in unpack(it) do
    k = key; for i=-1,li,-1 do
      k, v = it[i](k, v); if k == nil then goto skip end
    end
    to[k] = v
    ::skip::
  end
  return to
end

--- collect emitted [$v] as a list (keys are dropped)
Iter.valsTo = function(it, to) --> to
  local li, to, k, v = it._li, to or {}
  for key, v in unpack(it) do
    k = key; for i=-1,li,-1 do
      k, v = it[i](k, v); if k == nil then goto skip end
    end
    push(to, v)
    ::skip::
  end
  return to
end

--- collect emitted [$v] as a list (vals are dropped)
Iter.keysTo = function(it, to) --> to
  local li, to, k, v = it._li, to or {}
  for key, v in unpack(it) do
    k = key; for i=-1,li,-1 do
      k, v = it[i](k, v); if k == nil then goto skip end
    end
    push(to, k)
    ::skip::
  end
  return to
end

--- reset the iterator to run from the start
Iter.reset = function(it) it._nextK = it[3] end

--- use as an iterator.
Iter.__call = function(it, _, state)
  local li, k, v = it._li, it._nextK
  ::skip::
  k, v = it[1](it[2], k); if k == nil then return end
  it._nextK = k
  for i=-1,li,-1 do
    k, v = it[i](k, v); if k == nil then goto skip end
  end
  return k, v
end
Iter.iter = function(it)
  it._nextK = it[3]
  return it
end
Iter.__ipairs = ds.nosupport

return Iter
