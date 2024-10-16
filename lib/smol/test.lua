
local T = require'civtest'.Test
local smol = require'smol'
local fbin = require'fmt.binary'

local sfmt = string.format

local function rtest(base, change, expCmd, expText)
  print(('!! ### rtest (%q)  (%q)  ->  %q %q'):format(
    base, change, expCmd, expText))
  local cmds, text = smol.rdelta(change, base)
  print('!! cmds, text:', cmds, text)
  io.fmt:write('!! cmds\n')
  fbin.columns(io.fmt, cmds); io.fmt:write'\n'
  io.fmt:write('!! text\n')
  fbin.columns(io.fmt, text); io.fmt:write'\n'
  T.eq(change, smol.rpatch(cmds, text, base))
  if expCmd then
    T.binEq(expCmd, cmds)
    T.eq(expText, text)
  end
end

T.rdelta_small = function()
  -- hand-rolled decode
  local rp = smol.rpatch
  T.eq('abc',    rp('\x03',     'abc')) -- ADD
  T.eq('abcabc', rp('\x03\x83\x00', 'abc')) -- ADD+CPY
  T.eq('abc',    rp('\x83\x00', '', 'abc')) --CPY(base)

  rtest('',     '', '\0', '')
  rtest('base', '', '\0', '')
  rtest('',     'zzzzz',  '\x45', 'z') -- len=3 RUN(3, 'z')
  -- copy start
  rtest('01234567ab', '01234567yz',  '\x88\x02\x02', 'yz')
  -- copy end
  rtest('ab01234567', 'yz01234567',  '\x02\x88\x02', 'yz')

  rtest('01234567', 'a01234567z', '\x01\x88\x01\x01', 'az')
  rtest('', '0123456701234567', '\x08\x88\x00', '01234567')
end
