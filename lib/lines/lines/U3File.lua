local mty = require'metaty'
--- A file that holds 3 byte (24 bit) integers. These are commonly
--- used for indexing lines.
---
--- This object supports get/set index operations including appending.
--- Every operation (except consecutive writes) requires a file seek.
local U3File = mty'lines.U3File' {
  'fi [fd.IFile]',
}

local IFile = require'fd.IFile'
local pack, unpack = string.pack, string.unpack
local sfmt = string.format
local index, newindex = mty.index, mty.newindex

U3File.create = function(T, ...)
  local fi, err = IFile:create(3, ...)
  if not fi then return nil, err end
  return T{fi=fi}
end
U3File.reload = function(u3, mode) return u3.fi:reload(mode) end
U3File.load = function(T, ...)
  local fi, err = IFile:load(3, ...)
  if not fi then return nil, err end
  return T{fi=fi}
end

U3File.flush   = function(u3) return u3.fi:flush() end
U3File.__len   = function(u3) return u3.fi.len     end
U3File.__pairs = ipairs
U3File.close = function(u3) return u3.fi:close() end
U3File.__index = function(u3, k)
  if type(k) == 'string' then
    local mt = getmetatable(u3)
    return rawget(mt, k) or index(mt, k)
  end
  local str = u3.fi:__index(k)
  return str and unpack('>I3', str) or nil
end

U3File.__newindex = function(u3, k, v)
  if type(k) == 'string' then return newindex(u3, k, v) end
  return u3.fi:__newindex(k, pack('>I3', v))
end

U3File.__fmt = function(u3, fmt)
  push(fmt, 'U3File(')
  if u3.path then push(fmt, u3.path) end
  push(fmt, ')')
end

return U3File
