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
local function iseek(fi, i, sz) --> pos?, errmsg?
  if fi._i == i then return true end
  local to = (i-1) * sz
  local pos, err = fi.f:seek('set', to)
  if not pos then return pos, err end
  assert(pos % sz == 0, 'pos incorrect')
  return pos
end

--- This creates a new index file at path (path=nil uses tmpfile()).
--- Note: Use load if you want to load an existing index.
IFile.create = function(T, sz, path) --!> IFile
  assert(sz, 'must provide sz')
  local f, err
  if path then f, err = io.open(path, 'w+')
  else         f, err = io.tmpfile() end
  if not f then return failed{
    'create %s: %s', path or '(tmpfile)', err
  }end
  return T{sz=sz, f=f, len=0, _i = 1, path=path}
end

--- reload from path
IFile.reload = function(fi, mode) --!> IFile
  local f, err = io.open(fi.path, mode or 'r+')
  if not f then return failed{
    'reload %q mode=%s: %s', fi.path, mode or 'r+', err
  }end
  local sz, bytes = fi.sz, f:seek'end'
  -- truncate invalid bytes
  assert(f:seek('set', bytes - bytes % sz))
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

IFile.getbytes = function(fi, i) --!> str
  if i > fi.len then return end
  local sz = fi.sz; iseek(fi, i, sz)
  local v, err = fi.f:read(sz)
  if not v or (#v ~= sz) then return failed{'reading %i bytes: %s', sz, err} end
  fi._i = i + 1
  return v
end
IFile.__index = function(fi, i) --!> str
  if type(i) == 'string' then
    local mt = getmetatable(fi)
    return rawget(mt, i) or index(mt, i)
  end
  return fi:getbytes(i)
end

IFile.setbytes = function(fi, i, v) --> ok, errmsg?
  print('!! IFile setbytes', i, v)
  local len = fi.len
  if i > len + 1 then error(sfmt(
    'newindex OOB: %i > len=%i + 1', i, len
  ))end
  assert(i <= len + 1, 'newindex OOB')
  local sz = fi.sz
  if #v ~= sz then error('attempt to write '..#v..' bytes') end
  print('!! here')
  local r, err = iseek(fi, i, sz)
  if not r then return r, err or 'seek failed'end
  r, err = fi.f:write(v)
  if not r then return r, err or 'write failed' end
  print('!!   i, len', i, len)
  if i > len then fi.len = i end
  fi._i = i + 1
  return true
end
IFile.__newindex = function(fi, i, v)
  if type(i) == 'string' then return newindex(fi, i, v) end
  print('!! IFile newindex setbytes', i, v)
  assert(fi:setbytes(i, v))
end

IFile.__fmt = function(fi, fmt)
  fmt:write('IFile(sz=', tostring(fi.sz), ' ')
  if fi.path then fmt:write(fi.path) end
  fmt:write')'
end

return IFile
