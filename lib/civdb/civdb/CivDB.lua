local mty = require'metaty'
local CFile = require'civdb.CFile'

local construct = mty.construct

--- a database object backed by a civdb CFile
local CivDB = mty'civdb.CivDB' {
  'tf   [civdb.CFile]: file indexed by transaction index',
  'ridx [lines.U3File]: row -> transaction index',
}

getmetatable(CivDB).__call = function(T, path, mode)
  return construct(T, {rf=RowFile(path, mode or 'r+')})
end

CivDB.__len = function(db) return #db.ridx end
--- Create a new row with value, returning the row index.
CivDB.create = function(db, value) --> row
end

--- Read the row, returning its value
CivDB.read = function(db, row) --> value
end

--- Modify the value of the row with the value
CivDB.update = function(db, row, value)
end

--- Delete the row, future reads will return nil
CivDB.delete = function(db, index)
end

return CivDB
