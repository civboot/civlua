
local T = require'civtest'.Test
local smol = require'smol'

T.rdecode = function()
  T.eq('zzz', smol.rdecode('\x03\x43z')) -- len=3 RUN(3, 'z')
end
