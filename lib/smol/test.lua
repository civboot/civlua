
local T = require'civtest'.Test
local smol = require'smol'
local fbin = require'fmt.binary'

local sfmt = string.format

local function rtest(base, change, expCmd, expText)
  print(('!! ### rtest (%q)  (%q)  ->  %q %q'):format(
    base, change, expCmd, expText))
  local rdelta = smol.rdelta(change,  base)
  io.fmt:write('!! rdelta\n')
  fbin.columns(io.fmt, rdelta); io.fmt:write'\n'
  -- T.eq(change, smol.rpatch(rdelta, base))
  T.eq(change, smol.rpatch(expCmd, expText, base))

  -- if expCmd then T.binEq(expCmd, rdelta) end
end

T.rdelta_small = function()
  -- hand-rolled decode
  local rp = smol.rpatch
  T.eq('abc',    rp('\x03',     'abc')) -- ADD
  T.eq('abcabc', rp('\x03\x83\x00', 'abc')) -- ADD+CPY
  T.eq('abc',    rp('\x83\x00', '', 'abc')) --CPY(base)

  rtest('',     '', '\0')
  rtest('base', '', '\0')
  rtest('',     'zzzzz',  '\x05\x45z') -- len=3 RUN(3, 'z')
  -- copy start
  rtest('01234567ab', '01234567yz',  '\x0A\x88\x02\x02yz')
  -- copy end
  rtest('ab01234567', 'yz01234567',  '\x0A\x02yz\x88\x02')

  io.fmt:styled('error', '!!! this test\n')
  rtest('01234567', 'a01234567z', '\x0A\x01a\x88\x01\x01z')
  rtest('', '0123456701234567', '\x10\x0801234567\x88\x00')
end
