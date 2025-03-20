local mty = require'metaty'
--- Indexed File: supports setting and getting fixed-length values (bytes) by
--- index, implementing the API of a list-like table.
local IFile = mty'fd.IFile' {
  'f [file]', 'path [str]',
  'len [int]', '_i [int]',
  'sz [int]: the size of each value',
}

local mtype = math.type
local pack, unpack = string.pack, string.unpack
local sfmt = string.format
local trace = require'ds.log'.trace

local index, newindex = mty.index, mty.newindex

--- seek to index. Invariant: [$i <= len+1]
local function iseek(fi, i, sz) --!!> nil
  -- if fi._i == i then return end
  local to = (i-1) * sz
  -- print(sfmt('!! iseek %s i=%i sz=%i ==> %i',
  --   io.type(fi.f) or 'notIo', i, sz, to))
  local pos = assert(fi.f:seek('set', to))
  assert(pos % sz == 0, 'pos incorrect')
end

--- This creates a new index file at path (path=nil uses tmpfile()).
--- Note: Use load if you want to load an existing index.
IFile.create = function(T, sz, path) --> IFile?, errmsg?
  assert(sz, 'must provide sz')
  local f,e; if path then f,e = io.open(path, 'w+')
  else                    f,e = io.tmpfile() end
  if not f then return f,e end
  return T{sz=sz, f=f, len=0, _i = 1, path=path}
end

--- reload from path
IFile.reload = function(fi, mode) --> IFile?, errmsg?
  local f, err = io.open(fi.path, mode or 'r+')
  if not f then return nil, err end
  local sz, bytes = fi.sz, f:seek'end'
  f:seek('set', bytes - bytes % sz) -- truncate invalid bytes
  local len = bytes // sz
  fi.f, fi.len, fi._i = f, len, len + 1
  return fi
end

--- load an index file
IFile.load = function(T, sz, path, mode) --> IFile?, errmsg?
  assert(sz, 'must provide sz')
  return mty.construct(T, {sz=sz, path=path}):reload(mode)
end

IFile.flush   = function(fi) return fi.f:flush() end
IFile.__len   = function(fi) return fi.len       end
IFile.__pairs = ipairs

IFile.close = function(fi)
  if fi.f then fi.f:close(); fi.f = false end
end

--- get bytes. If index out of bounds return nil.
--- Panic if there are read errors.
IFile.getbytes = function(fi, i) --!!> str?
  if i > fi.len then return end
  local sz = fi.sz; iseek(fi, i, sz)
  local v = assert(fi.f:read(sz))
  assert(#v == sz, 'did not read sz bytes')
  fi._i = i + 1
  return v
end
IFile.__index = function(fi, i)
  if type(i) == 'string' then
    local mt = getmetatable(fi)
    return rawget(mt, i) or index(mt, i)
  end
  return fi:getbytes(i)
end

IFile.setbytes = function(fi, i, v)
  local len = fi.len; assert(i <= len + 1, 'newindex OOB')
  local sz = fi.sz
  if #v ~= sz then error(sfmt('failed to write %i bytes', #v)) end
  print(sfmt('!! IFile.setbytes i=%i _i=%i sz=%i', i, fi._i, sz))
  iseek(fi, i, sz); assert(fi.f:write(v))
  if i > len then fi.len = i end
  fi._i = i + 1
end
IFile.__newindex = function(fi, i, v)
  if type(i) == 'string' then return newindex(fi, i, v) end
  return fi:setbytes(i, v)
end

IFile.__fmt = function(fi, fmt)
  fmt:write('IFile(sz=', tostring(fi.sz), ' ')
  if fi.path then fmt:write(fi.path) end
  fmt:write')'
end

return IFile
