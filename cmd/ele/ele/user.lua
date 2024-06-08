-- User module: set up actual usage
local M = mod and mod'ele.user' or {}
local et = require'ele.types'

local lap = require'lap'
local yield = coroutine.yield

-- schedule keyinput coroutines
M.keyinput = function(data, evsend)
  local keys = lap.Recv()
  table.insert(data.resources, keys)
  LAP_READY[
    coroutine.create(et.term.input, keys:sender())
  ] = 'terminput'
  lap.schedule(function()
    while data.run do
      local key = keys()
      if key then evsend{key, action='keyinput'} end
      ::cont::
    end
  end)
end

return M
