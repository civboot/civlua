local G = G or _G
--- civdb: minimalistic CRUD database
local M = G.mod and mod'civdb' or setmetatable({}, {})
local S = require'civdb.sys'

local sfmt, byte = string.format, string.byte
local encv, decv = S.encv, S.decv

--- Start a row by encoding the length.
--- It is the caller's job to actually write the row data.
M.startrow = function(file, len) --> byteswritten?, err
  len = encv(len); assert(file:write(len), 'write error')
  return #len
end

--- read the next row from a file, decoding the length with decv
--- Return the row and the length of the encv integer encoding.
M.readrow = function(file) --> (string?, lensz|error)
  local len, sh, s = 0, 0
  while true do
    s = file:read(1); if not s then return nil end
    local b = byte(s); len = ((0x7F & b) << sh) | len
    if (0x80 & b) ~= 0 then sh = sh + 7 else break end
  end
  s = file:read(len); if not s then return nil, 'read row data' end
  if not s or len ~= #s then
    return nil, sfmt('did not read full len: %i ~= %i', len, #s)
  end
  return s, (sh + 7) // 7
end

return M
