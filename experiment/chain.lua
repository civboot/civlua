local M = mod and mod'rebuf.chain' or {}
local mty = require'metaty'
local ds  = require'ds'

-- A slice of src from startindex:endindex
M.Slice = mty'Slice' { 'src', 'si [int]', 'ei [int]' }

-- Indexed file that can be mutated. Mutations are stored as gap buffers.
M.MutIdxFile = mty'MutIdxFile' {
  'idxf [IndexedFile]',
  'deq [ds.Deq[Slice|Gap]]',
  '_len [int]',
}
getmetatable(M.Chain).__call = function(T, idxf)
  local t = {idxf=idxf, deq=ds.Deq{}, _len=#idxf}
  t.deq:push(M.Slice{src=idxf, si=1, ei=t._len})
  return mty.construct(T, t)
end

M.Chain.__len = function(ch) return rawget(ch, '_len') end

return M
