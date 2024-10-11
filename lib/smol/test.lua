
local T = require'civtest'.Test
local smol = require'smol'

T.rdecode = function()
  T.eq('zzz', smol.rdecode('\x43z'))
end
