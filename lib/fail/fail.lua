local push, concat = table.insert, table.concat
local unpack = table.unpack
local sfmt = string.format
local setmt, getmt = setmetatable, getmetatable
local raweq = rawequal

--- The fail type and module. See README.cxt for usage.
local fail = setmetatable({__name = 'fail'}, {
  __name = 'failtype',
  __call = function(F, f) return setmt(f, F) end,
})

--- The fail type. See module documentation.
fail.__tostring = function(f) return sfmt(unpack(f)) end

--- return true if rawequal(getmt(v), fail).
---
--- Typical use is [$if failed(v) then return v end] to propogate
--- a failure to the caller.
fail.failed = function(v) return raweq(getmt(v), fail) end

--- throw error if [$v] is falsy or fail.
fail.assert = function(v, ...) --> v, ...
  if not v then error((...) or 'assert failed')    end
  if raweq(getmt(v), fail) then error(tostring(v)) end
  return v, ...
end

--- Convert lua's standard [$ok, errmsg] to fail when not ok.
---
--- This is useful to return the result of "standard" lua (ok, errmsg) APIs.
fail.check = function(ok, errmsg) return ok or fail{errmsg} end

return fail
