local mty = require'metaty'
local RowFile = require'civdb.RowFile'

local construct = mty.construct

--- a database object backed by a RowFile
local CivDB = mty'civdb.CivDB' {
  'f   [civdb.File]: rowfile containing the data and main index',
}

getmetatable(CivDB).__call = function(T, path, mode)
  return construct(T, {rf=RowFile(path, mode or 'r+')})
end

CivDB.create = function(db, row) --> index
end

CivDB.read = function(db, index) --> row
end

CivDB.update = function(db, index, row)
end

CivDB.delete = function(db, index)
end

return CivDB
