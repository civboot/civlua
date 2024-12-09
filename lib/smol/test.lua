
local T = require'civtest'.Test
local smol = require'smol'
local S = require'smol.sys'
local fbin = require'fmt.binary'
local ds = require'ds'
local pth = require'ds.path'
local Iter = require'ds.Iter'
local civix = require'civix'

local sfmt = string.format

local function rtest(base, change, expCmd, expText)
  print(('!! ### rtest (%q)  (%q)  ->  %q %q'):format(
    base, change, expCmd, expText))
  local x = S.createX{fp4po2=14}
  local cmds, text = smol.rdelta(change, x, base)
  print('!! cmds, text:', cmds, text)
  io.fmt:write('!! cmds\n')
  fbin.columns(io.fmt, cmds); io.fmt:write'\n'
  io.fmt:write('!! text\n')
  fbin.columns(io.fmt, text); io.fmt:write'\n'
  T.eq(change, smol.rpatch(cmds, text, x, base))
  if expCmd then
    T.binEq(expCmd, cmds)
    T.eq(expText, text)
  end
  return cmds, text
end

T.rdelta_small = function()
  -- hand-rolled decode
  local rp = smol.rpatch
  local x = S.createX{fp4po2=14}
  T.eq('abc',    rp('\x03',     'abc', x)) -- ADD
  T.eq('abcabc', rp('\x03\x83\x00', 'abc', x)) -- ADD+CPY
  T.eq('abc',    rp('\x83\x00', '',        x, 'abc')) --CPY(base)

  rtest('',     '', '\0', '')
  rtest('base', '', '\0', '')
  rtest('',     'zzzzz',  '\x45', 'z') -- len=3 RUN(3, 'z')
  -- copy start                       cpy8@2   ad2
  rtest('01234567ab', '01234567yz',  '\x88\x02\x02', 'yz')
  -- copy end                         ad2  cpy8@2
  rtest('ab01234567', 'yz01234567',  '\x02\x88\x02', 'yz')

  -- copy base w/fingerprint        ad1  cpy8@1 ad1
  rtest('01234567', 'a01234567z', '\x01\x88\x01\x01', 'az')
  -- copy nobase w/fingerprint      ad8 cpy8@0
  rtest('', '0123456701234567',   '\x08\x88\x00', '01234567')
end

T.huffman_small = function()
  local x = S.createX{fp4po2=14}
  local txt = "AAAA   zzzz;;"
  assert(S.htree(x, 0, txt), nil)
  local enc = assert(S.hencode(txt, x))
  print(sfmt("Enc len=%i: %q\n", #enc, enc))
  assert(false, 'okay')
end

local function testpath(x, path)
  local ftext = ds.readPath(path)
  local xmds, txt, csize = S.rdelta(ftext, x)
  if not xmds then csize = #ftext -- no compression
  else
    csize = #xmds + #txt
    T.eq(#ftext, S.rcmdlen(xmds))
    T.eq(ftext, S.rpatch(xmds, txt, x))
  end
  print(sfmt('compress % 8i / %-8i (%3i%%) : %s',
    csize, #ftext, math.floor(csize * 100 / #ftext), pth.nice(path)))
  return csize, #ftext
end

T.compress_files = function()
  local x = S.createX{fp4po2=14}
  testpath(x, 'cmd/cxt/test.lua')
end

T.walk_compress = function()
  local x = S.createX{fp4po2=14}
  local num, csize, osize = 0, 0, 0
  for path, ftype in civix.Walk{'./'} do
    if ftype ~= 'file' or path:find'/%.'
      or path:find'experiment' then
      goto continue end
      local c, o = testpath(x, path)
      num = num + 1; csize = csize + c; osize = osize + o
    ::continue::
  end
  print(sfmt('!! average compression of %i individual files', num))
  print(sfmt('  == %i/%i (%.0f%%)',
        csize, osize, (csize * 100) / osize))
end
