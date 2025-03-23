local G = G or _G

--- test runners and helpers for lap
local M = G.mod and G.mod'lap.testing' or {}

local lap = require'lap'
local ix  = require'civix'

M.lapRunner = function(test)
  local lr = ix.Lap()
  local _, errors = lr:run{test}
  if errors then error(
    'lapRunner found errors:\n'..require'fmt'(errors)
  )end
  if not lr:isDone() then
    error'lapRunner had no errors but is not done!'
  end
  lap.reset()
end

return M
