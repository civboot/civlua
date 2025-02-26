local mty = require'metaty'
local fail = require'fail'
local check, failed, fassert = fail.check, fail.failed, fail.assert

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

local index, newindex = mty.index, mty.newindex

--- seek to index. Invariant: [$i <= len+1]
local function iseek(fi, i, sz) --> pos!
  if fi._i == i then return end
  local to = (i-1) * sz
  local pos = check(fi.f:seek('set', to))
  if failed(pos) then return pos end
  assert(pos % sz == 0, 'pos incorrect')
  return pos
end

--- This creates a new index file at path (path=nil uses tmpfile()).
--- Note: Use load if you want to load an existing index.
IFile.create = function(T, sz, path) --> IFile!, err
  assert(sz, 'must provide sz')
  local f; if path then f = check(io.open(path, 'w+'))
           else         f = check(io.tmpfile()) end
  if failed(f) then return f end
  return T{sz=sz, f=f, len=0, _i = 1, path=path}
end

--- reload from path
IFile.reload = function(fi, mode)
  local f = check(io.open(fi.path, mode or 'r+'))
  if failed(f) then return f end
  local sz, bytes = fi.sz, f:seek'end'
  -- truncate invalid bytes
  local r = check(f:seek('set', bytes - bytes % sz))
  if failed(r) then return r end
  local len = bytes // sz
  fi.f, fi.len, fi._i = f, len, len + 1
  return fi
end

--- load an index file
IFile.load = function(T, sz, path, mode)
  assert(sz, 'must provide sz')
  return mty.construct(T, {sz=sz, path=path}):reload(mode)
end

IFile.flush   = function(fi) return check(fi.f:flush()) end
IFile.__len   = function(fi) return fi.len       end
IFile.__pairs = ipairs

IFile.close = function(fi)
  if fi.f then fi.f:close(); fi.f = false end
end

IFile.getbytes = function(fi, i)
  if i > fi.len then return end
  local sz = fi.sz; iseek(fi, i, sz)
  local v = check(fi.f:read(sz)); if failed(v) then return v end
  if #v ~= sz then return failed{'did not read %i bytes', sz} end
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
  if #v ~= sz then error('attempt to write '..#v..' bytes') end
  local r = iseek(fi, i, sz); if failed(r) then return r end
  r = check(fi.f:write(v));   if failed(r) then return r end
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
