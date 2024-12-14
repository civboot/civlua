
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
  local cmds, text = S.rdelta(change, x, base)
  print('!! cmds, text:', cmds, text)
  io.fmt:write('!! cmds\n')
  fbin.columns(io.fmt, cmds); io.fmt:write'\n'
  io.fmt:write('!! text\n')
  fbin.columns(io.fmt, text); io.fmt:write'\n'
  T.eq(change, S.rpatch(cmds, text, x, base))
  if expCmd then
    T.binEq(expCmd, cmds)
    T.eq(expText, text)
  end
  return cmds, text
end

T.rdelta_small = function()
  -- hand-rolled decode
  local rp = S.rpatch
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
  print('!! txt len: ', #txt)
  -- Note:
  -- ';' = 00   ' ' = 01
  -- 'A' = 10   'z' = 11
  assert(S.htree(x, 0, txt), nil)
  local enc = assert(S.hencode(txt, x))
  T.binEq(
  -- len AAAA   zzz
    '\x0D\xAA\x57\xFC\x00',
    enc)

  print(sfmt("Enc len=%i: %q\n", #enc, enc))
  local dec, err = assert(S.hdecode(enc, x));
  print(sfmt("Dec len=%i: %q", #dec, dec))
  print(sfmt("Dec err: %q", err));
  assert(not err)
  T.binEq(txt, dec);
end

-- Note: esz (encoding sz) substracts the length byte
local function htest(txt, esz)
  print(('!! ### htest %q'):format(txt))
  local x = S.createX{fp4po2=14}
  assert(S.htree(x, 0, txt))
  local h = assert(S.hencode(txt, x))
  print(sfmt("!! ##### htest %q (%i) -> %q (%i)", txt, #txt, h, #h))
  local res = assert(S.hdecode(h, x))
  T.binEq(txt, res)
  if esz then T.eq(esz, #h - 1) end
end

T.huffman = function()
  htest('abcdefg', 3) htest('00000', 1) htest('01010101', 1)
  htest('abaabbcccddaa', 4)
end

local test_encv = function(v, len)
  local e = S.encv(v);       T.eq(len, #e)
  local d, elen = S.decv(e); T.eq(len, elen)
  T.eq(v, d)
end

T.encv = function()
  test_encv(0, 1); test_encv(1, 1); test_encv(0x37, 1); test_encv(0x7F, 1)
  test_encv(0x080, 2); test_encv(0x100, 2); test_encv(0x3FFF, 2);
  test_encv(0x4000, 3);
  test_encv(0x7FFFFFFF, 5);
end

local function print_stats(name, path, tsize, csize)
  print(sfmt('  %-10s: compress % 8i / %-8i (%3i%%) : %s',
    name, csize, tsize, math.floor(csize * 100 / tsize), pth.nice(path)))
end
local function rdelta_testpath(sm, path)
  local ftext = ds.readPath(path)
  local xmds, txt = S.rdelta(ftext, sm.x); local csize
  if not xmds then csize = #ftext -- no compression
  else
    csize = #xmds + #txt
    T.eq(#ftext, S.rcmdlen(xmds))
    T.eq(ftext, S.rpatch(xmds, txt, sm.x))
  end
  print_stats('rdelta', path, #ftext, csize)
  return csize, #ftext
end

local function huff_testpath(sm, path) --> encsz, pathsz
  local ftext = ds.readPath(path)
  if ftext == '' then print('skipping: '..path); return end
  assert(S.htree(sm.x, 0, ftext))
  local enc = S.hencode(ftext, sm.x)
  local dec = S.hdecode(enc, sm.x)
  local ok, btree = S.htree(sm.x, 2); assert(ok, btree)
  print_stats('huff', path, #ftext, #btree + #enc)
  T.binEq(ftext, dec)
  return #btree + #enc, #ftext
end

local function smol_testpath(sm, path) --> encsz, pathsz
  local ftext = ds.readPath(path)
  local enc = sm:compress(ftext)
  local dec = sm:decompress(enc)
  print_stats('smol', path, #ftext, #enc)
  T.binEq(ftext, dec)
  return #enc, #ftext
end

T.compress_files = function()
  local sm = smol.Smol{}
  rdelta_testpath(sm, 'cmd/cxt/test.lua')
  huff_testpath(sm,   'cmd/cxt/test.lua')
  smol_testpath(sm,   'cmd/cxt/test.lua')
end

T.walk_compress = function()
  local sm = smol.Smol{}
  local num, osize, rsize, hsize = 0, 0, 0, 0
  for path, ftype in civix.Walk{'./'} do
    if ftype ~= 'file' or path:find'/%.'
      or path:find'experiment' then
      goto continue end
      print("compressing "..pth.nice(path))
      local r, o = rdelta_testpath(sm, path); rsize = rsize + r
      local h    = huff_testpath(sm, path);   hsize = hsize + h
      num = num + 1; osize = osize + o
    ::continue::
  end
  print(sfmt('!! average compression of %i individual files', num))
  print(sfmt('  rdelta == %i/%i (%.0f%%)', rsize, osize, (rsize * 100) / osize))
  print(sfmt('  huff   == %i/%i (%.0f%%)', hsize, osize, (hsize * 100) / osize))
  error'ok'
end
