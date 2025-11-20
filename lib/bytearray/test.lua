
local bytearray = require'bytearray'
local T = require'civtest'
local ds = require'ds'

T.basic = function()
  T.eq('bytearray', bytearray.__name)
  T.eq('bytearray type', getmetatable(bytearray).__name)

  local b = bytearray"test data";
  T.eq('test data', tostring(b))
  T.eq('test data', b:to())
end

ds.yeet'bytearray works'
