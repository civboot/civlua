local mty = require'metaty'

--- Robinhood hashing index for field (column)
local HashIdx = mty'civdb.HashIdx' {
  'db [civdb.DB]',
  'field [str]: the hashed field (key)',
}

--- Return an iterator for [$civdb.Query], using hash index for [$op=EQ]
HashIdx.__call = function(idx, q) --> iter (row, val)
end

--- handle a newly created value at row
HashIdx.create = function(idx, row, val)
end

--- handle an updated value at row
HashIdx.update = function(idx, row, val)
end

--- handle an deleted value at row
HashIdx.delete = function(idx, row)
end


return HashIdx
