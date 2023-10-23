local mty = require'metaty'
local smol = require'smol'

local sfmt = string.format

local M = {}

function M.assertFilesEq(p1, p2)
  local p = io.popen(sfmt('diff -q %s %s', p1, p2))
  local msg = p:read()
  assert(p:close(), msg)
end

M.VERIFY_TXT = 'out/verify.txt'
M.VERIFY_ENC = 'out/verify.enc'
M.VERIFY_DEC = 'out/verify.dec'

M.verify = mty.doc[[verify an encoder.
]](function(name, bits, inpIsPath, inp, encoder, decoder)
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
    file=encf,
    bits=bits,
  }
  local enc = coroutine.wrap(encoder)
  enc(inp, bits)

  local numCodes = 0
  local encAndStore = function()
    local code = enc(); if not code then return end
    numCodes = numCodes + 1
    -- mty.pntf('!! encoded %8X -> ', code or -1)
    encw(code, bits)
    return code
  end

  -- This tests direct pass-through
  local dec = coroutine.wrap(decoder)
  dec(encAndStore, bits)
  for str in dec do
    -- mty.pntf('!! decoded          -> %q', str)
    decf:write(str)
  end
  encw:finish(); decf:flush()
  local inpSize, encSize = inp:seek(), encf:seek()
  M.assertFilesEq(inpPath, M.VERIFY_DEC)
  mty.pntf('REPORT %s % 3ibits: %s:  %.1f%%  %i/%i kiB',
    name, bits, inpPath, 100 * encSize / inpSize, encSize//1024, inpSize//1024
  )

  -- mty.pntf('!! Decoding from encoded file bits')
  -- This tests that we can decode the file itself
  encf:seek'set'; decf:seek'set'
  local readCodes = smol.ReadBits{
    file=encf, bits=bits,
  }
  local dec = coroutine.wrap(decoder)
  dec(readCodes, bits)
  for _=1,numCodes do
    local str = assert(dec())
    -- mty.pntf('!! decoded2 -> %q', str)
    decf:write(str)
  end

  inp:close();  readCodes.file:close();
  decf:flush(); decf:close()
  M.assertFilesEq(inpPath, M.VERIFY_DEC)

  return inpSize, encSize
end)

return M
