local G = G or _G

--- test runners and helpers for civix
local M = G.mod and G.mod'civix.testing' or {}

local fmt = require'fmt'
local lap = require'lap'
local ix  = require'civix'

--- Typically an entire test file is wrapped in a function,
--- then passed to this -- which runs all tests sequentially
--- inside the lap environment.
---
--- ["This does not print test names/etc. Use civtest or
---   equivalent for that.
--- ]
M.runAsyncTest = function(fn)
  local lr = ix.Lap()
  local _, errors = lr:run{test}
  if errors then error(
    'testLapEnv found errors:\n'..fmt(errors)
  )end
  if not lr:isDone() then
    error'testLapEnv had no errors but is not done!'
  end
  lap.reset()
end

return M

