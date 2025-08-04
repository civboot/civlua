local mty = require'metaty'
local ds  = require'ds'
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

getmetatable(U3File).__index = mty.hardIndex
U3File.__newindex            = mty.hardNewindex

U3File.create = function(T, ...) return icreate(T, 3, ...)  end
U3File.load   = function(T, ...) return iload(T, 3, ...)    end

--- get value at index
U3File.get = function(u3, i)
  local str = getbytes(u3, i)
  return str and unpack('>I3', str) or nil
end

--- set value at index
U3File.set = function(u3, i, v)
  return setbytes(u3, i, pack('>I3', v))
end

U3File.__fmt = function(u3, fmt)
  push(fmt, 'U3File(')
  if u3.path then push(fmt, u3.path) end
  push(fmt, ')')
end

U3File.extend = ds.defaultExtend
U3File.icopy  = ds.defaultICopy

return U3File
