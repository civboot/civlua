local mty = require'metaty'

--- Usage: [$freeze.freezy(MyType)] to make MyType freezable, see
--- [<#metaty.freeze.freezy>].
---
--- Call usage: [$freeze(v)][{br}]
--- When called: freezes the value, see [<#metaty.freeze.freeze>].
local M = mty.mod'metaty.freeze'

--- Frozen values. Generally this should not be accessed.
--- The keys are the frozen tables which are "weak" so the GC can collect
--- them if they have no other references.
M.FROZEN = setmetatable({}, {__mode='k'})
local FROZEN = M.FROZEN

local sfmt = string.format
local type, getmt, setmt   = type, getmetatable, setmetatable
local rawget, rawset       = rawget, rawset
local next, pairs, rawlen  = next, pairs, rawlen

local freeze

-- freeze the values in a table.
-- It is the metamethod jobs to check FROZEN[self] to ensure it stays
-- not-mutated.
local function freezeTable(t)
  if FROZEN[t] then return t end
  local fr = {}
  for k, v in next, t, nil do
    fr[k] = freeze(v); t[k] = nil
  end
  FROZEN[t] = fr
  return t
end

local function iden(v) return v end

function M.frozenNext(f, k) return next(FROZEN[f], k) end
local frozenNext = M.frozenNext

M._freezyPairs = function(r)
  local fr = FROZEN[r]; if fr then return frozenNext, r, nil end
  return next, r, nil
end

M._freezyLen = function(r)
  local fr = FROZEN[r]; if fr then return #fr end
  return rawlen(r)
end

--- A "plain old table" that has been frozen (made immutable).
M.frozen = mty'frozen' {}; local frozen = M.frozen
getmetatable(frozen).__call = function(T, self)
  return setmt(freezeTable(self), T)
end
frozen.__len   = M._freezyLen
frozen.__pairs = M._freezyPairs
function frozen:__index(k) return rawget(FROZEN[self] or self, k) end
function frozen:__newindex(k, v)
  if FROZEN[self] then error(sfmt('Attempt to set key %q to frozen table', k)) end
  rawset(self, k, v)
end
frozen.__metatable = 'table'

--- Usage: [$MyType.__index = mty._freezyIndex][{br}]
--- This is the [$__index] set by [<#freeze>]. It retrieves from FROZEN (if it
--- exists), else returns the default or falls back to [$getmt(R).__index].
M._freezyIndex = function(r, k)
  -- first, get from frozen
  local fr, v = FROZEN[r]; if fr then
    v = fr[k]; if v ~= nil then return v end
  end
  local R = getmt(r)
  -- then, get from default
  v = rawget(R, k); if v ~= nil then return v end
  -- else, fallback to erorr checking (field existence)
  return getmt(R).__index(R, k)
end

M._freezyNewindex = function(r, k, v)
  return FROZEN[r] and error(sfmt('Attempt to set key %q to frozen value', k))
      or getmt(r).newindex(r, k, v)
end

local FREEZE_TYPE = {
  ['nil'] = iden, boolean = iden, number = iden, string = iden,
  ['function'] = iden,
  ['userdata'] = function(u) return FROZEN[u] and u or assert(u:freeze()) end,
  table = function(t)
    return FROZEN[t] and t
        or getmt(t) and assert(t:freeze())
        or frozen(t)
  end,
}

--- Freeze value, making it immutable.
---
--- Implementation: If [$v] is a table, the table's actual values are moved
--- to a table in [$freeze.FROZEN], which is where they are retrieved.
--- [$__index], etc are frozen to give an immutable "view" into this table.
---
--- If [$v] is userdata, [$:freeze()] is called on it.
---
--- Concrete lua values are already immutable. Functions are considered
--- already frozen, it is the author's responsibility to ensure functions don't
--- mutate state.
function M.freeze(v)
  return (FREEZE_TYPE[type(v)] or error('unfreezeable type: '..type(v)))(v)
end
freeze = M.freeze

--- Usage: [$M.MyType = freeze.freezy(mty'MyType' { ... })][{br}]
--- Make the type [$:freeze()]-able, after which it will be immutable.
---
--- This has a performance cost both before and after the value is frozen.
---
--- ["Through three cheese trees three free fleas flew.[{br}]
---   While these fleas flew, freezy breeze blew.[{br}]
---   Freezy breeze made these three trees freeze.[{br}]
---   Freezy trees made these trees' cheese freeze.[{br}]
---   That's what made these three free fleas sneeze.[{br}]
---   - Dr Seuss, "Fox in Socks"
--- ]
M.freezy = function(R)
  assert(not rawget(R, 'index',    'already has index'))
  assert(not rawget(R, 'newindex', 'already has newindex'))
  assert(not rawget(R, '__len',    'already has __len'))
  assert(not rawget(R, '__pairs',  'already has __pairs'))
  rawset(R, 'index', R.__index)
  rawset(R, '__index', M._freezyIndex)
  if type(R.index) == 'table' then
    assert(R.index == R, '__index was unexpected table')
    R.index = nil
  end
  rawset(R, 'newindex',   R.__newindex)
  rawset(R, '__newindex', M._freezyNewindex)
  rawset(R, '__len',      M._freezyLen)
  rawset(R, '__pairs',    M._freezyPairs)
  rawset(R, 'freeze',     freezeTable)
  rawset(R, 'fmt',        nil)
  return R
end

--- Return whether v is immutable.
function M.isFrozen(v)
  return (FREEZE_TYPE[type(v)]==iden) or (FROZEN[v] and true) or false
end

--- Force set the value, even on a frozen type. Obviously,
--- this should be used with caution.
function M.forceset(t, k, v)
  local fr = FROZEN[t]; if fr then fr[k] = v
  else                             t[k]  = v end
end

getmetatable(M).__call = function(_, v) return freeze(v) end
return M
