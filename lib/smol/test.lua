
local T = require'civtest'.Test
local smol = require'smol'

T.rdecode = function()
  local rd = smol.rdecode
  T.eq('', rd'\0'); T.eq('', rd('\0', 'base'))
  T.eq('zzz',    rd'\x03\x43z')           -- len=3 RUN(3, 'z')
  T.eq('abc',    rd'\x03\x03abc')         -- len=3 ADD(3, 'abc')
  T.eq('abcabc', rd'\x06\x03abc\x83\x02') -- ... CPY(3, 2)
  T.eq('abc',    rd('\x03\x83\x02', 'abc')) -- base CPY(3,2)
end
