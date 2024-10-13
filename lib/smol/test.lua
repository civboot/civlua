
local T = require'civtest'.Test
local smol = require'smol'
local fbin = require'fmt.binary'

local sfmt = string.format

local function rtest(base, change, edelta)
  print(('!! ### rtest (%q)  (%q)  ->  %q'):format(base, change, edelta))
  local rdelta = smol.rdelta(change,  base)
  T.eq(change, smol.rpatch(rdelta, base))

  if edelta then T.binEq(edelta, rdelta) end
end

T.rdelta_small = function()
  -- hand-rolled decode
  local rp = smol.rpatch
  T.eq('abc',    rp'\x03\x03abc')         -- len=3 ADD(3, 'abc')
  T.eq('abcabc', rp'\x06\x03abc\x83\x00') -- ... CPY(3, 2)
  T.eq('abc',    rp('\x03\x83\x00', 'abc')) -- base CPY(3,2)

  rtest('',     '', '\0')
  rtest('base', '', '\0')
  rtest('',     'zzzzz',  '\x05\x45z') -- len=3 RUN(3, 'z')
  -- copy start
  rtest('01234567ab', '01234567yz',  '\x0A\x88\x02\x02yz')
  -- copy end
  rtest('ab01234567', 'yz01234567',  '\x0A\x02yz\x88\x02')

  -- rtest('',     'abcdabcdabcd', '\x0C\x04abcd\x84\x00\x84\x00')
end
