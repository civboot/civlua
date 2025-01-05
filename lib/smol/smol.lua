local G = G or _G
--- small compression algorithms
local M = G.mod and mod'smol' or {}
local S = require'smol.sys'

local mty = require'metaty'
local construct = mty.construct
local char, byte = string.char, string.byte

local rdelta, rpatch          = S.rdelta, S.rpatch
local calcHT                  = S.calcHT
local encodeHT, decodeHT      = S.encodeHT, S.decodeHT
local hencode, hdecode        = S.hencode, S.hdecode
local encv, decv              = S.encv, S.decv

local sfmt = string.format
local assertEq = require'civtest'.Test.eq
local assertBinEq = require'civtest'.Test.binEq
local fbin = require'fmt.binary'

local RDELTA, HUFF_CMDS, HUFF_RAW = 0x80, 0x40, 0x20

M.XConfig = mty'XConfig' {
  'fp4po2 [int]: max size of len4 fingerprint table', fp4po2=14,
}

M.Smol = mty'Smol' {
  'x [smol.X]: holds settings and buffers for smol operations',
  'rdelta [bool]: whether to use rdelta in compress',
  'huff   [bool]: whether to use huffman coding in compress and rdelta',
}

getmetatable(M.Smol).__call = function(T, t)
  t.x = S.createX(t.x or M.XConfig{})
  return construct(T, t)
end

-- encode text usin ghuffman encoding. Tree is included at the front
M.Smol.hencode = function(sm, text) --> htree..enc
  assert(calcHT(sm.x, text))
  local ht  = assert(encodeHT(sm.x))

  -- FIXME: remove these checks for decode equality
  assertEq(#ht, assert(decodeHT(sm.x, ht..string.rep('Z', 1024))))
  local htStr = S.fmtHT(sm.x)
  assertEq(htStr:gsub('#%d+', '#0'), S.fmtHT(sm.x))

  local enc = assert(hencode(text, sm.x))
  local elen, lensz = S.decv(enc)
  assertEq(#text, elen)
  print(fbin(enc)); print""
  print("!! check decoding, elen:", elen, "(encoded in", lensz, "bytes)")
  assertBinEq(text, hdecode(enc, sm.x))

  return ht..enc
end

-- decode huffman tree+encoded bytes.
M.Smol.hdecode = function(sm, henc) --> text
  print("!! Smol.hdecode.tree #henc=", #henc)
  local treelen = assert(decodeHT(sm.x, henc))
  print("!! Smol.hdecode treelen=", treelen)
  return assert(hdecode(henc:sub(treelen+1), sm.x))
end

M.Smol.compress = function(sm, text, base)
  print("!! Smol.compress "..#text)
  if text == '' then return '' end
  local cmds, raw = rdelta(text, sm.x, base)

  local hcmds = assert(sm:hencode(cmds))
  local hraw  = assert(sm:hencode(raw))

  -- FIXME: remove checks
  assertEq(text, rpatch(cmds, raw, sm.x, base))
  assertEq(cmds, sm:hdecode(hcmds))
  assertEq(raw, sm:hdecode(hraw))

  return char(RDELTA | HUFF_CMDS | HUFF_RAW)..encv(#hcmds)..hcmds..hraw
end

M.Smol.decompress = function(sm, enc, base)
  print("!! Smol.decompress "..#enc)
  if enc == '' then return '' end
  assert((RDELTA | HUFF_CMDS | HUFF_RAW) == byte(enc:sub(1,1)))
  local cmdlen, elen = decv(enc:sub(2,10))
  print("!! elen", elen)
  local si = 1 + elen
  local hcmds = enc:sub(si, si + cmdlen - 1)
  local hraw  = enc:sub(si + cmdlen)
  print(sfmt("!! decompress hcmds (%i): %q\n", #hcmds, hcmds))
  print(sfmt("!! decompress hraw  (%i): %q\n", #hcmds, hraw))

  local cmds = sm:hdecode(hcmds)
  local raw  = sm:hdecode(hraw)
  -- print(sfmt("!! decompress cmds:\n%s\n", fbin(cmds)))
  -- print(sfmt("!! decompress raw :\n%s\n", fbin(raw)))
  return rpatch(cmds, raw, sm.x, base)
end

return M
