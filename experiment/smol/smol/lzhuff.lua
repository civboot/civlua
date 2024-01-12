-- LZW + Huffman

local pkg = require'pkg'
local mty = require'metaty'
local lzw  = require'smol.lzw'
local huff = require'smol.huff'

local M = mty.docTy({}, [[
LZW compresses local, huffman compresses common LZW codes.
The algorithms are orthogonal to eachother so you get
effectively double compression.
]])

M.encoder = mty.doc[[(codes, bits) -> huff.Encoder, tree
]](function(codes, bits)
  return huff.Encoder(lzw.Encoder(codes, bits), huff.eof(bits))
end)

M.decoder = mty.doc[[(rb, bits, htree) -> lzw.Decoder
]](function(rb, bits, htree)
  -- local tdbg = huff.treeStr(htree)
  -- for i, s in ipairs(tdbg) do
  --   if i < 200 or i > #tdbg - 200 then
  --     print(s)
  --   end
  -- end
  return lzw.Decoder(huff.Decoder(rb, bits, htree), bits)
end)

return M
