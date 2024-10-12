
local T = require'civtest'.Test
local smol = require'smol'
local fbin = require'fmt.binary'

local function rtest(base, change, encoded)
  print(('!! ### rtest (%q)  (%q)  ->  %q'):format(base, change, encoded))
  if encoded then
    T.eq(change,  smol.rpatch(encoded, base))
  end
  local rd = smol.rdelta(change,  base)
  T.eq(fbin(encoded), not rd and '<!nil!>' or fbin(rd))
end

T.rdelta_small = function()
  -- hand-rolled decode
  local rp = smol.rpatch
  T.eq('abc',    rp'\x03\x03abc')         -- len=3 ADD(3, 'abc')
  T.eq('abcabc', rp'\x06\x03abc\x83\x00') -- ... CPY(3, 2)
  T.eq('abc',    rp('\x03\x83\x00', 'abc')) -- base CPY(3,2)

  rtest('',     '', '\0')
  rtest('base', '', '\0')
  rtest('',     'zzzzz',    '\x05\x45z') -- len=3 RUN(3, 'z')
  -- rtest('',     'abcdabcdabcd', '\x0C\x04abcd\x84\x00\x84\x00')
end
