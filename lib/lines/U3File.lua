local mty = require'metaty'
local ds  = require'ds'
local IFile = require'ds.IFile'

--- A file of 3 byte (24 bit) integers. These are commonly
--- used for indexing lines.
---
--- This object supports get/set index operations including appending. Every
--- operation (except consecutive reads/writes) requires a file seek.
local U3File = mty.extendMod(IFile, 'lines.U3File', {})

local pack, unpack = string.pack, string.unpack
local sfmt = string.format
local index, newindex = mty.hardIndex, mty.newindex

local icreate, ireload, iload = IFile.create, IFile.reload, IFile.load
local getbytes, setbytes = IFile.getbytes, IFile.setbytes

getmetatable(U3File).__index = mty.hardIndex
U3File.__newindex            = mty.hardNewindex

U3File.create = function(T, ...) return icreate(T, 3, ...)  end
U3File.load   = function(T, ...) return iload(T, 3, ...)    end

--- get value at index
function U3File:get(i)
  local str = getbytes(self, i)
  return str and unpack('>I3', str) or nil
end

--- set value at index
function U3File:set(i, v)
  return setbytes(self, i, pack('>I3', v))
end

function U3File:__fmt(fmt)
  push(fmt, 'U3File(')
  if self.path then push(fmt, self.path) end
  push(fmt, ')')
end

U3File.extend = ds.defaultExtend
U3File.icopy  = ds.defaultICopy

return U3File
