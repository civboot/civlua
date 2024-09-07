local mty = require'metaty'
-- EdFile: an editable file object, optimized for indexed and consequitive
-- reads and writes.
local EdFile = mty'EdFile' {
  'f   [file]: open file', 'path [string]',
  'idx [U3File]: line index of f',
  'dats [list]: list of Slc | Gap',
  'lens [list]: rolling sum of dat lengths for O(n) line lookup',
}

local ds = require'ds'
local U3File = require'lines.U3File'

-- Create a new EdFile (default idx=lines.U3File()).
local EdFile.create = function(T, path, idx) --> EdFile
  local f, err = io.open(path, 'w+'); if not f   then return nil, err end
  if idx then assert(#idx == 0, 'idx must be empty')
  else
    idx, err = U3File:create();       if not idx then return nil, err end
  end
  return mty.construct(T, {
    f=f, idx=idx,
    dats={ds.Slc{si=1, ei=0}},
    lens={0},
  })

end


return EdFile
