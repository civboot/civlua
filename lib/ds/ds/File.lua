local mty = require'metaty'

-- Base file object which defers to File.f
--
-- Example way to extend it:
--   M.MyFile = mty.extend(require'ds.File', 'MyFile', {'newField'})
--   M.MyFile.write = function(f, ...) --[[ overwrite write ]] end
--   local f = assert(MyFile:open('path/to/file.txt', 'w'))
--   f:write'foo'
local File = mty'ds.File' {
  'f[file]', 'path[string]', 'mode [string]'
}
File.open = function(T, path, mode)
  local f, err = io.open(path, mode)
  if not f then return nil, err end
  return T{f=f, path=path, mode=mode}
end

File.read  = function(f, ...)   return f:read(...)  end
File.lines = function(f, ...)   return f:lines(...)  end
File.write = function(f, ...)   return f:write(...) end
File.flush = function(f, ...)   return f:flush(...) end
File.seek  = function(f, ...)   return f:seek(...)  end
File.setvbuf = function(f, ...) return f:setvbuf(...)  end

return File
