
local mty = require'metaty'
local ds = require'ds'
local heap = require'ds.heap'

local char, byte = string.char, string.byte
local co         = coroutine
local push = table.insert

local M = mty.docTy({}, [[smol: data compression algorithms to make data smaller.]])

local B8 = {
  0x01, 0x03, 0x07, 0x0F,
  0x1F, 0x3F, 0x7F, 0xFF,
}; M.BITMASK8 = B8

function M.bitsmax(bits) assert(bits <= 32); return (1 << bits) - 1 end

M.FileCodes = mty.doc[[FileCodes(file): file as 8bit codes.]]
(mty.record'FileCodes')
  :field('file', 'userdata')
:new(function(ty_, file) return mty.new(ty_, {file=file}) end)
M.FileCodes.reset = function(fc) fc.file:seek'set' end
M.FileCodes.__call = function(fc)
  local c = fc.file:read(1)
  return c and byte(c) or nil
end

---------------------
-- Bits: writing and reading packed bits to/from a file-like object.
-- Compression is all about making things as small as possible, so there is a
-- very strong need to pack bits together. This makes it easy.
M.WriteBits = mty.doc[[Write bits as big-endian.
Example:
  wb = WriteBits{file=io.open(path, 'wb'), bits=12}
  wb(1055)
  wb.file:flush(); wb.file:close()
]]
(mty.record'WriteBits')
  :field('file', 'userdata')
  :fieldMaybe('bits', 'number')
  :field('_data',     'number', 0) -- max 0xFF
  :field('_dataBits', 'number', 0) -- 1-8

M.WriteBits.__call = function(wb, n, bits)
  bits = assert(bits or wb.bits, 'no bits'); assert(bits > 0)
  local data, dataBits = wb._data or 0, wb._dataBits
  while bits > 0 do
    local mbits = math.min(8 - dataBits, bits) -- minBits
    assert(mbits > 0, mbits)
    data = (data << mbits) | ((n >> (bits - mbits)) & B8[mbits])
    dataBits, bits = dataBits + mbits, bits - mbits
    if dataBits >= 8 then
      assert(dataBits == 8, dataBits)
      assert(data <= 0xFF, data)
      wb.file:write(char(data))
      data, dataBits = 0, 0
    else break end
  end
  wb._data, wb._dataBits = data, dataBits
end

M.WriteBits.finish = mty.doc[[write any leftover data and flush.]]
(function(wb)
  if wb._dataBits > 0 then
    wb.file:write(char(wb._data << (8 - wb._dataBits)))
  end
  wb._data, wb._dataBits = nil, nil
  wb.file:flush()
end)

M.ReadBits = mty.doc[[Read bits as big-endian

  rb = ReadBits{file=io.open(path, 'rb'), bits=12}
  my12bitvalue = rb()
]]
(mty.record'ReadBits')
  :field('file', 'userdata')
  :fieldMaybe('bits', 'number')
  :field('_data',     'number', 0) -- max 0xFF
  :field('_dataBits', 'number', 0) -- 1-8

M.ReadBits.__call = function(rb, bits)
  bits = assert(bits or rb.bits, 'no bits')
  local n, data, dataBits = 0, rb._data, rb._dataBits
  while bits > 0 do
    if dataBits == 0 then
      data, dataBits = rb.file:read(1), 8
      if data then data = byte(data)
      else dataBits = 0; return end
    end
    local mbits = math.min(bits, dataBits) -- minBits
    n = (n << mbits) | ((data >> (dataBits - mbits)) & B8[mbits])
    bits, dataBits = bits - mbits, dataBits - mbits
  end
  rb._data, rb._dataBits = data, dataBits
  return n
end

---------------------
-- LZW
M.lzw = mty.docTy({}, [[
lzw: implementation of Lempel–Ziv–Welch compresion algorithm.
  See README for a full description of the algorithm.
]])

local function lzwEncDict()
  local d = {}; for b=0,0xFF do d[char(b)] = b end; return d
end

local function lzwDecDict()
  local d = {}; for b=0,0xFF do d[b] = char(b) end; return d
end

M.lzw.Encoder = mty.doc[[(file, bits) -> codesIter
Example:
  for code in lzw.Encoder(io.open(path, 'rb'), 12) do
    ... do something with code like WriteBits
  end
]](mty.record'lzw.Encoder')
  :field'codes'
  :field('dict',     'table')
  :field('max',      'number')
  :field('word',     'string')
  :field('nextCode', 'number')
:new(function(ty_, codes, bits)
  return mty.new(ty_, {
    codes=codes, dict=lzwEncDict(),
    max=M.bitsmax(assert(bits)), word='', nextCode=0x100,
  })
end)
M.lzw.Encoder.reset = function(enc)
  enc.codes:reset()
  enc.dict = lzwEncDict()
  enc.word, enc.nextCode = '', 0x100
end
M.lzw.Encoder.__call = function(enc)
  local word, dict = enc.word, enc.dict
  if enc.nextCode <= enc.max then
    for b in enc.codes do
      local c = char(b)
      local wordc = word..c
      if dict[wordc] then word = wordc
      else
        dict[wordc] = enc.nextCode; enc.nextCode = enc.nextCode + 1
        enc.word = c; return dict[word]
      end
    end
  end
  for b in enc.codes do
    local c = char(b)
    local wordc = word..c
    if dict[wordc] then word = wordc
    else enc.word = c; return dict[word] end
  end
  if #word > 0 then enc.word = ''; return dict[word] end
end


M.lzw.Decoder = mty.doc[[lzw.Decoder(codes, bits) -> stringIter
Example:
  local dec = coroutine.wrap(lzw.decode)
  for str in lzw.Decoder(rb, 12) do
    ... do something with str like write to file.
  end
]](mty.record'lzw.Decoder')
  :field'codes'
  :field('dict',     'table')
  :field('max',      'number')
  :field('nextCode', 'number')
  :field('i',        'number')
  :fieldMaybe('word', 'string')
:new(function(ty_, codes, bits)
  local word = codes()
  return mty.new(ty_, {
    codes=codes, dict=lzwDecDict(),
    max=M.bitsmax(assert(bits)),
    word=word and char(word) or nil,
    i=0, nextCode=0x100,
  })
end)
M.lzw.Decoder.reset = function(dec)
  dec.codes:reset()
  local word = codes()
  dec.dict = lzwDecDict()
  dec.word = word and char(word) or nil
  dec.i = 0; dec.nextCode = 0x100
end
M.lzw.Decoder.__call = function(dec)
  local word, dict = dec.word, dec.dict
  dec.i = dec.i + 1;      if dec.i == 1 then return word end
  local code = dec.codes(); if not code then return end
  if dec.nextCode <= dec.max then
    local entry = dict[code]
    if entry then -- pass, found code
    elseif code == dec.nextCode then
      -- special case #3 (see README)
      entry = word..word:sub(1,1)
    else mty.errorf('invalid code: 0x%X', code) end
    dict[dec.nextCode] = word..entry:sub(1,1)
    dec.nextCode = dec.nextCode + 1
    dec.word = entry
    return entry
  end
  return assert(dict[code])
end

---------------------
-- Huffman Coding

M.huff = mty.docTy({}, [[
Huffman Coding: use less data by making commonly used codes smaller and less
commonly used codes larger.
]])

M.huff.eof = function(bits) return 1 << bits end

local function huffcmp(p, c) return p.freq < c.freq end

M.huff.tree = mty.doc[[Construct a huffman binary tree.
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

local function treeNode(d, node, hcode, bits)
  if node.code then d[node.code] = {hcode, bits}
  else
    assert(node[1] and node[2])
    treeNode(d,node[1],          hcode, bits+1) -- 0=left
    treeNode(d,node[2],(1<<bits)|hcode, bits+1) -- 1=right
  end
end
local function treeDict(root)
  local d = {}; treeNode(t, root, 0, 0)
  return t
end

-- leaf: write 1 + code bits
-- else: write 0
local function writeTree(wb, node, bits)
  if node.code then wb(1, 1); wb(node.code, bits)
  else              wb(0, 1)
    assert(node[1] and node[2])
    writeTree(wb, node[1], bits)
    writeTree(wb, node[2], bits)
  end
end
local function readTree(rb, bits)
  if rb(1) == 1 then return rb(bits)
  else return {readTree(rb, bits), readTree(rb, bits)} end
end

M.huff.writeTree = mty.doc[[
write the tree using pre-order traversal.
  writeTree(writeBits, tree, bits)

]](writeTree)
M.huff.readTree = mty.doc[[
read the tree from writeTree.
  readTree(readBits, bits) -> tree

Nodes are {left,right}, leaves are the code number.
]](readTree)

function M.huff.readTree(rb, bits)
  if rb(1) == 1 then return rb(bits)
  else return {readTree(rb, bits), readTree(rb, bits)} end
end

M.huff.Encoder = mty.doc[[
Encoder using huffman codes.

  huff.Encoder(codes, eof [,tree]) -> encoder, tree

Each call to the encoder returns {hcode, bits}
where `bits` is the size of the hcode in bits.

Example:
  local fc = smol.FileCodes(io.open(read, 'rb'))
  local enclzw    = lzw.Encoder(fc, bits)
  local enc, tree = huff.Encoder(enclzw, huff.eof(bits))
  local wb = smol.WriteBytes(io.open(write, 'wb'))
  huff.writeTree(wb, tree, bits) -- encode the tree
  for cb in enc do
    local code, bits = cb
    wb(code, bits)
  end

Note: If tree is not provided this constructs the tree
      then calls codes:reset().
]](mty.record'huff.Encoder')
  :field'codes'
  :field('eof', 'number')
  :field('dict', 'table')
  :field('done', 'boolean', false)
:new(function(ty_, codes, eof, tree)
  assert(eof, 'must provide eof')
  if not tree then
    tree = M.huff.tree(codes, eof)
    codes:reset()
  end
  return mty.new(ty_, {
    codes=codes, eof=eof,
    dict=treeDict(tree),
  }), tree
end)
M.huff.reset = function(he)
  he.codes:reset()
  he.done = nil
end
M.huff.Encoder.__call = function(he)
  local code = he.codes(); if not code then
    if he.done then return end
    he.done = true; return he.dict[he.eof]
  end
  return mty.assertf(he.dict[code], 'unknown code %s', code)
end

M.huff.Decoder = mty.doc[[
Decoder from huffman codes.

  huff.Decoder(rb, eof, tree) -> stringIter

Example:
  local rb = smol.ReadBits(io.open(read, 'rb'))
  local tree = huff.readTree(rb, bits) -- or from Encoder(...)
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
    readBits=rb, bits=bits, tree=tree,
    eof=eof or M.huff.eof(bits),
  })
end)
M.huff.Decoder.reset = function(hd)
  hd.codes:reset()
  hd.done = false
end
M.huff.Decoder.__call = function(hd)
  if hd.done then return end
  local rb, node = hd.readBits, hd.tree
  while type(node) ~= 'number' do
    local bit = assert(rb(1), 'readBits empty before EOF')
    if bit == 0 then node = node[1]     -- go left
    else             node = node[2] end -- go right
    assert(node)
  end
  if node == hd.eof then hd.done = true
  else return node end
end

return M
