-- LZW encoding

local pkg = require'pkglib'
local mty = require'metaty'
local smol = require'smol'
local char, byte = string.char, string.byte
local push = table.insert

local M = mty.docTy({}, [[
lzw: implementation of Lempel–Ziv–Welch compresion algorithm.
  See README for a full description of the algorithm.
]])

local function lzwEncDict()
  local d = {}; for b=0,0xFF do d[char(b)] = b end; return d
end

local function lzwDecDict()
  local d = {}; for b=0,0xFF do d[b] = char(b) end; return d
end

M.Encoder = mty.doc[[(codes, bits) -> codesIter
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
    max=smol.bitsmax(assert(bits)), word='', nextCode=0x100,
  })
end)
M.Encoder.reset = function(enc)
  enc.codes:reset()
  enc.dict = lzwEncDict()
  enc.word, enc.nextCode = '', 0x100
end
M.Encoder.__call = function(enc)
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


M.Decoder = mty.doc[[lzw.Decoder(codes, bits) -> stringIter
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
    max=smol.bitsmax(assert(bits)),
    word=word and char(word) or nil,
    i=0, nextCode=0x100,
  })
end)
M.Decoder.reset = function(dec)
  dec.codes:reset()
  local word = codes()
  dec.dict = lzwDecDict()
  dec.word = word and char(word) or nil
  dec.i = 0; dec.nextCode = 0x100
end
M.Decoder.__call = function(dec)
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
    dec.word = entry
    word = word..entry:sub(1,1)
    dict[dec.nextCode] = word; dec.nextCode = dec.nextCode + 1
    return entry
  end
  return assert(dict[code])
end

return M
