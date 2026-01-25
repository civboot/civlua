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
local getmt, setmt = getmetatable, setmetatable
local rawget, rawset       = rawget, rawset
local next, pairs, rawlen  = next, pairs, rawlen

local function iden(v) return v end

--- A "plain old table" that has been frozen (made immutable).
M.frozen = mty'frozen' {}
getmetatable(M.frozen).__call = function(T, self)
  return setmt(self, T):freeze()
end
local frozen = M.frozen

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

M._freezyNewindex = function(r, k)
  if FROZEN[r] then error(sfmt('Attempt to set key %q to frozen value', k)) end
  return getmt(r).newindex(r, k)
end

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
local freeze = M.freeze

--- The [$FreezyType:freeze()] method.
function M._freezeMethod(self)
  local fr = {}
  for k, v in pairs(self) do
    fr[k] = freeze(v); self[k] = nil
  end
  FROZEN[self] = fr
  return self
end

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
  assert(not R.index,    'already has index')
  assert(not R.newindex, 'already has newindex')
  assert(not R.__len,    'already has __len')
  assert(not R.__pairs,  'already has __pairs')
  R.index, R.__index = R.__index, M._freezyIndex
  if type(R.index) == 'table' then
    assert(R.index == R, '__index was unexpected table')
    R.index = nil
  end
  R.newindex, R.__newindex = R.__newindex, M._freezyNewindex
  R.__len,    R.__pairs    = M._freezyLen, M._freezyPairs
  R.freeze = M._freezeMethod
  return R
end

getmetatable(frozen).__index = function() end
frozen.__newindex = rawset
M.freezy(frozen)

getmetatable(M).__call = function(_, v) return freeze(v) end
return M
