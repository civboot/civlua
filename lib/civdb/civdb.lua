local G = G or _G
--- civdb: minimalistic CRUD database
local M = G.mod and mod'civdb' or setmetatable({}, {})
local S = require'civdb.sys'
local encv, decv = S.encv, S.decv

--- Write a row of data to a file encoding the length with encv.
M.writerow = function(file, str) --> byteswritten?, err
  local encsz = encv(#str)
  file:write(encsz);
  local ok, err = file:write(str); if not ok then return nil, err end
  return #encsz + #str
end

--- read the next row from a file, decoding the length with decv
--- Return the row and the length of the encv integer encoding.
M.readrow = function(file) --> (string, lensz/error)
  local s = file:read(8); if not s or #s == 0 then return end
  local len, lensz = decv(s)
  local row, err = file:read(len - (#s - lensz))
  row = s:sub(lensz+1)..row
  if(len ~= #row) then
    return nil, 'corrupted row length: '..len..' != '..#row
  end
  return row, lensz
end

return M
