local G = G or _G

--- small compression algorithms
local M = G.mod and mod'smol' or {}
local S = require'smol.sys'

local mty = require'metaty'
local construct = mty.construct
local char, byte = string.char, string.byte

local HTREE_CALC, HTREE_READ, HTREE_GET = 0, 1, 2
local rdelta, rpatch          = S.rdelta, S.rpatch
local htree, hencode, hdecode = S.htree, S.hencode, S.hdecode
local encv, decv              = S.encv, S.decv

local RDELTA              = 0x80
local HUFF_CMDS, HUFF_RAW = 0x08, 0x04

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
  assert(htree(sm.x, M.HTREE_CALC, text))
  local ok, ht = htree(sm.x, M.HTREE_GET); assert(ok, ht)
  local enc, err = hencode(text, sm.x);    assert(not err, err)
  return ht..enc
end

M.Smol.hdecode = function(sm, henc) --> text
  local ok, treelen = htree(sm.x, HTREE_READ, henc); assert(ok, treelen)
  return assert(hdecode(henc:sub(treelen), sm.x))
end

M.Smol.compress = function(sm, text, base)
  if text == '' then return '' end
  local cmds, raw = rdelta(text, x, base)
  local hcmds = assert(sm.hencode(cmds))
  local hraw  = assert(sm.hencode(raw))
  return char(RDELTA | HUFF_CMDS | HUFF_RAW)..encv(#hcmds)..hcmds..hraw
end

M.Smol.decompress = function(sm, enc, base)
  if enc == '' then return '' end
  assert((RDELTA | HUFF_CMDS | HUFF_RAW) == byte(enc:sub(1,1)))
  local cmdlen, elen = decv(enc:sub(2,10))
  local si = 1 + elen
  local hcmds, hraw = enc:sub(si, si + cmdlen - 1), enc:sub(si + cmdlen)
  local cmds, raw = sm:hdecode(hcmds), sm:hdecode(hraw)
  return rpatch(cmds, raw, sm.x)
end

return M
