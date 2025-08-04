local mty = require'metaty'
local IFile = require'fd.IFile'

--- A file that holds 3 byte (24 bit) integers. These are commonly
--- used for indexing lines.
---
--- This object supports get/set index operations including appending.
--- Every operation (except consecutive writes) requires a file seek.
local U3File = mty.extend(IFile, 'lines.U3File', {})

local pack, unpack = string.pack, string.unpack
local sfmt = string.format
local index, newindex = mty.index, mty.newindex

local icreate, ireload, iload = IFile.create, IFile.reload, IFile.load
local getbytes, setbytes = IFile.getbytes, IFile.setbytes

U3File.create = function(T, ...) return icreate(T, 3, ...)  end
U3File.load   = function(T, ...) return iload(T, 3, ...)    end
U3File.__index = function(u3, k)
  if type(k) == 'string' then
    local mt = getmetatable(u3)
    return rawget(mt, k) or index(mt, k)
  end
  local str = getbytes(u3, k)
  return str and unpack('>I3', str) or nil
end

U3File.__newindex = function(u3, k, v)
  if type(k) == 'string' then return newindex(u3, k, v) end
  return setbytes(u3, k, pack('>I3', v))
end

U3File.__fmt = function(u3, fmt)
  push(fmt, 'U3File(')
  if u3.path then push(fmt, u3.path) end
  push(fmt, ')')
end

return U3File
