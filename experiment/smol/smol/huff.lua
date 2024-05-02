-- Huffman Coding
local pkg = require'pkglib'
local mty = pkg'metaty'
local ds = pkg'ds'
local heap = pkg'ds.heap'

local char, byte = string.char, string.byte
local sfmt = string.format
local push = table.insert

local M = mty.docTy({}, [[
Huffman Coding: use less data by making commonly used codes smaller and less
commonly used codes larger.
]])

M.eof = function(bits) return 1 << bits end

local function huffcmp(p, c) return p.freq < c.freq end

M.tree = mty.doc[[Construct a huffman binary tree.
nodes are {left, right, freq=freq}. Leaf nodes have node.code.
]]
(function(encoder, eof)
  local freq, lo, hi = {}, nil, nil
  for code in encoder do
    local n = freq[code]; if not n then
      n = {freq=0, code=code}; freq[code] = n
    end
    n.freq = n.freq + 1
  end
  assert(not freq[eof], 'eof is not unique')
  freq[eof] = {freq=0, code=eof}

  local hp = {}; for _, v in pairs(freq) do push(hp, v) end
  hp, freq = heap.Heap(hp, huffcmp), nil
  while #hp > 1 do
    local n = {hp:pop(), hp:pop()} -- left, right
    n.freq = n[1].freq + n[2].freq
    hp:add(n)
  end
  return hp:pop()
end)

local function _treeStrip(node)
  if node.code then return node.code
  else
    node.freq = nil
    local v; assert(node[1] and node[2])
    v = _treeStrip(node[1]); if v then node[1] = v end
    v = _treeStrip(node[2]); if v then node[2] = v end
  end
end

M.treeStrip = mty.doc[[treeStrip(tree)
Perform inplace strip of tree.
]](function(root)
  if root.code then return root.code end
  _treeStrip(root)
  return root
end)

local function dictNode(d, node, hcode, bits)
  local code = type(node) == 'number' and node or node.code
  if code then d[code] = {hcode, bits}
  else
    assert(node[1] and node[2])
    dictNode(d, node[1], (hcode<<1)  , bits+1) -- 0=left
    dictNode(d, node[2], (hcode<<1)|1, bits+1) -- 1=right
  end
end
local function treeDict(root)
  local d = {}; dictNode(d, root, 0, 0)
  return d
end

-- leaf: write 1 + code bits
-- else: write 0
local function writeTree(wb, node, bits)
  local code = type(node) == 'number' and node or node.code
  if code then wb(1, 1); wb(code, bits)
  else         wb(0, 1)
    assert(node[1] and node[2])
    writeTree(wb, node[1], bits)
    writeTree(wb, node[2], bits)
  end
end
local function readTree(rb, bits)
  if rb(1) == 1 then return rb(bits)
  else return {readTree(rb, bits), readTree(rb, bits)} end
end

M.writeTree = mty.doc[[
write the tree using pre-order traversal.
  writeTree(writeBits, tree, bits)

]](writeTree)
M.readTree = mty.doc[[
read the tree from writeTree.
  readTree(readBits, bits) -> tree

Nodes are {left,right}, leaves are the code number.
]](readTree)

function M.readTree(rb, bits)
  if rb(1) == 1 then return rb(bits)
  else return {readTree(rb, bits), readTree(rb, bits)} end
end

M.Encoder = mty.doc[[
Encoder using huffman codes.

  huff.Encoder(codes, eof [,tree]) -> encoder, tree

Each call to the encoder returns hcode, bits
where `bits` is the size of the hcode in bits.

Example:
  local fc = smol.FileCodes(io.open(read, 'rb'))
  local enclzw    = lzw.Encoder(fc, bits)
  local enc, tree = huff.Encoder(enclzw, huff.eof(bits))
  local wb = smol.WriteBytes(io.open(write, 'wb'))
  huff.writeTree(wb, tree, bits) -- encode the tree
  for code, bits in enc do
    wb(code, bits)
  end

Note: If tree is not provided this constructs the tree
      then calls codes:reset().

Note: if you want to pass the tree to the decoder (instead
      of encoding it in the file) then you must use
      huff.treeStrip(tree)
]](mty.record'huff.Encoder')
  :field'codes'
  :field('eof', 'number')
  :field('dict', 'table')
  :field('done', 'boolean', false)
:new(function(ty_, codes, eof, tree)
  assert(eof, 'must provide eof')
  if not tree then
    tree = M.tree(codes, eof)
    codes:reset()
  end
  return mty.new(ty_, {
    codes=codes, eof=eof,
    dict=treeDict(tree),
  }), tree
end)
M.reset = function(he)
  he.codes:reset()
  he.done = nil
end
M.Encoder.__call = function(he)
  local code = he.codes(); if not code then
    if he.done then return end
    he.done = true; return table.unpack(he.dict[he.eof])
  end
  local res, bits = table.unpack(he.dict[code])
  return res, bits
end

M.Decoder = mty.doc[[
Decoder from huffman codes.

  huff.Decoder(rb, eof, tree) -> stringIter

Example:
  local rb = smol.ReadBits(io.open(read, 'rb'))
  -- Alternatively strip tree from Encoder(...)
  local tree = huff.readTree(rb, bits) 
  local hdec = huff.Decoder(rb, bits, tree)
  local lzdec = lzw.Decoder(hdec, bits)
  local outf = io.open(write, 'wb')
  for str in lzdec do
    outf:write(str)
  end
  outf:flush()
]](mty.record'huff.Decoder')
  :field'readBits'
  :field('bits', 'number')
  :field'tree'
  :field('eof', 'number')
  :field('done', 'boolean', false)
:new(function(ty_, rb, bits, tree, eof)
  return mty.new(ty_, {
    readBits=rb, bits=bits,
    tree=assert(tree),
    eof=eof or M.eof(bits),
  })
end)
M.Decoder.reset = function(hd)
  hd.codes:reset()
  hd.done = false
end
M.Decoder.__call = function(hd)
  if hd.done then return end
  local rb, node, code = hd.readBits, hd.tree
  while true do
    code = type(node) == 'number' and node or node.code
    if code then break end
    local bit = assert(rb(1), 'readBits empty before EOF')
    if bit == 0 then node = node[1]     -- go left
    else             node = node[2] end -- go right
    assert(node)
  end
  if code == hd.eof then hd.done = true
  else return code end
end

-- debug a huffman tree
local function _treeStr(t, node, hcode)
  if node.code then
    push(t, {hcode=hcode, code=node.code, freq=node.freq})
  else
    if node[1] then _treeStr(t, node[1], hcode..'0') end
    if node[2] then _treeStr(t, node[2], hcode..'1') end
  end
end
function M.treeStr(root)
  local t = {}; _treeStr(t, root, '')
  table.sort(t, function(l, r) return #l.hcode < #r.hcode end)
  local d = {}; for i, v in ipairs(t) do
    push(d, sfmt('%3i, % 6i, 0x%04X, %q, %s',
         i, v.freq, v.code, char(0xFF & v.code), v.hcode))
  end
  return d
end


function M.easyEncoder(codes, bits)
  return M.Encoder(codes, M.eof(bits))
end

function M.easyDecoder(codes, bits, tree)
  -- print('# Tree\n'..table.concat(M.treeStr(tree), '\n'))
  return M.Decoder(codes, bits, M.treeStrip(tree))
end


return M
