local mty = require'metaty'
--- a database object backed by a civdb CFile
local CivDB = mty'civdb.CivDB' {
  'tf   [civdb.CFile]: file indexed by transaction index',
  'ridx [lines.U3File]: row -> transaction index',
}

local pth = require'ds.path'
local civdb = require'civdb'
local CFile = require'civdb.CFile'
local construct = mty.construct
local loadIdx = require'lines.File'._loadIdx

local encode, decode = civdb.encode, civdb.decode

CivDB.IDX_DIR = pth.concat{pth.home(), '.data/rows'}

CivDB.Op = mty'Op' {
  'kind [string]: create, delete or update',
  'row  [int]: the row index',
  'tidx [int]: the previous transaction index (create/delete only)',
}

-- encode an operation. Operations are encoded as lua values
-- which are then encoded by civdb.encode
local OP_ENCODE = {
  -- create a row and record what the row number is
  create = function(rowNum)          return rowNum end,
  -- update a row with backreference to previous tidx
  update = function(rowNum, oldTidx) return {rowNum,  oldTidx} end,
  -- delete a row with backreference to previous tidx
  delete = function(rowNum, oldTidx) return {rowNum, -oldTidx} end,
}

CivDB.Op.encode = function(op) return OP_ENCODE[op.kind](op.row, op.tidx) end

--- Op:decode(val) - decode the operation.
CivDB.Op.decode = function(T, t)
  if type(t) == 'number' then return T{op='create', row=t} end
  local t1, t2 = t[1], t[2]; assert(type(t1) == 'number', 'not implemented')
  if t1 >= 0 then return T{op='update', row=t1, tidx= t2}
  else            return T{op='delete', row=t1, tidx=-t2} end
end

--- Get the operation from the transaction file
--- Returns the txbytes and opLen so the value can (optionally) be decoded.
local readOperation = function(tf, i) --> txbytes, op, oplen
  local tx = tf[i]; if not tx then return end
  local op, opLen = decode(tx)
  return tx, decodeOp(op), opLen
end

local readTransaction = function(tf, i)
  local tx = assert(tf[i])
  local opt, optlen = decode(tx)
  local val = decode(tx, optlen + 1)
end

getmetatable(CivDB).__call = function(T, path, mode)
  mode = mode or 'r+'
  local tf, err, ridx = CFile(path, mode)
  if not tf then return nil, err end
  if not path then
    ridx, err = U3File:create(); if not ridx then return nil, err end
  else
    ridx, err = loadIdx(T, tf, path, mode)
    if not ridx then return nil, err end
  else error'invalid path' end
  return construct(T, {tf=tf, ridx=ridx})
end

CivDB._reindex = function(tf, ridx, l, pos)
  l, pos = l or 1, pos or 0
  if #tf == 0 then return end
  -- FIXME: walk transactions, update rowidx
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
