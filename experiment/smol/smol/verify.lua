local pkg = require'pkg'
local mty  = pkg'metaty'
local smol = require'smol'

local sfmt, push = string.format, table.insert

local M = {}

function M.assertFilesEq(p1, p2)
  local p = io.popen(sfmt('diff -q %s %s', p1, p2))
  local msg = p:read()
  assert(p:close(), msg)
end

M.VERIFY_TXT = '.out/verify.txt'
M.VERIFY_ENC = '.out/verify.enc'
M.VERIFY_DEC = '.out/verify.dec'

local function encodeDirect(inpPath, bits, encw, enc)
  for code, cbits in enc do
    -- mty.pnt('!! encodeDirect', code, cbits)
    encw(code, cbits)
  end
  encw:finish()
end

-- Gives nice debug info but is impossible for huffman
local function encodeWatch(inpPath, bits, encw, enc, decf, decoder)
  local encAndStore = function()
    local code, cbits = enc(); if not code then return end
    mty.pntf('## encoded %8X ->%s', code or -1,
             cbits and ('  ('..cbits..'bits)') or '')
    encw(code, cbits or bits)
    return code, cbits
  end

  -- This tests direct pass-through
  local dec = decoder(encAndStore, bits, encState)
  for str in dec do
    mty.pntf('## decoded          -> %q', str)
    decf:write(str)
  end
  encw:finish(); decf:flush()
  M.assertFilesEq(inpPath, M.VERIFY_DEC)
end

M.verify = mty.doc[[Verify encoding.
]](function(name, bits, inpIsPath, inp, encoder, decoder, set)
  set = set or {}
  local finalDecode = set.finalDecode or mty.identity
  local inpPath
  if inpIsPath then inpPath, inp = inp, io.open(inp, 'rb')
  else
    inpPath = M.VERIFY_TXT
    local f = io.open(inpPath, 'w+b')
    f:write(inp); f:flush(); f:seek'set'
    inp = f
  end

  local decf = io.open(M.VERIFY_DEC, 'w+b') -- decoded file
  local encf = io.open(M.VERIFY_ENC, 'w+b')
  local encw = smol.WriteBits{                 -- encoded bits
    file=assert(encf),
    bits=bits,
  }
  local inpc = smol.FileCodes(inp)
  local enc, encExtra = encoder(inpc, bits)

  if set.watch then
    encodeWatch(inpPath, bits, encw, enc, decf, decoder)
  else
    encodeDirect(inpPath, bits, encw, enc)
  end

  local inpSize, encSize = inp:seek(), encf:seek()
  mty.pntf('REPORT %s % 3ibits: %s:  %.1f%%  %i/%i kiB',
    name, bits, inpPath, 100 * encSize / inpSize, encSize//1024, inpSize//1024
  )

  -- mty.pntf('!! Decoding from encoded file bits')
  -- This tests that we can decode the file itself
  encf:seek'set'; decf:seek'set'
  local readCodes = smol.ReadBits{
    file=encf, bits=bits,
  }
  local dec = decoder(readCodes, bits, encExtra)
  for code in dec do
    local str = finalDecode(code)
    -- mty.pntf('!! decoded2 -> %q', str)
    decf:write(str)
  end

  decf:flush()
  inp:close(); decf:close(); readCodes.file:close();
  M.assertFilesEq(inpPath, M.VERIFY_DEC)

  return inpSize, encSize
end)

return M
