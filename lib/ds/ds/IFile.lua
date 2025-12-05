local mty = require'metaty'
local ds = require'ds'

--- Indexed File: supports setting and getting fixed-length values (bytes) by
--- index, implementing the API of a list-like table.
local IFile = mty'ds.IFile' {
  'f [file]', 'path [str]', 'mode [str]',
  'len [int]', '_i [int]', '_m [str]: r/w mode',
  'sz [int]: the size of each value',
}

local mtype = math.type
local pack, unpack = string.pack, string.unpack
local sfmt = string.format
local info = require'ds.log'.info

getmetatable(IFile).__index = mty.hardIndex
IFile.__newindex            = mty.hardNewindex

--- seek to index in the "mode" m. Invariant: [$i <= len+1]
local function iseek(fi, i, m, sz) --!!> nil
  if fi._i == i and fi._m == m then return end
  fi._m = m
  local to = (i-1) * sz
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
  return T{sz=sz, f=f, len=0, _i = 1, path=path, mode='w+'}
end

--- Reload IFile from path.
IFile.reload = function(fi) --> IFile?, errmsg?
  local f, err = io.open(fi.path, fi.mode or 'r+')
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
  return mty.construct(T, {sz=sz, path=path, mode=mode}):reload()
end

IFile.flush   = function(fi) return fi.f:flush() end
IFile.__len   = function(fi) return fi.len       end
IFile.__pairs = ipairs

IFile.close = function(fi)
  if fi.f then fi.f:close(); fi.f = false end
end
IFile.closed = function(fi) --> bool
  return fi.f and true or false
end

--- get bytes. If index out of bounds return nil.
--- Panic if there are read errors.
IFile.getbytes = function(fi, i) --!!> str?
  if i > fi.len then return end
  local sz = fi.sz; iseek(fi, i, 'r', sz)
  local v = assert(fi.f:read(sz))
  assert(#v == sz, 'did not read sz bytes')
  fi._i = i + 1
  return v
end
IFile.get = IFile.getbytes

IFile.setbytes = function(fi, i, v)
  local len = fi.len; assert(i <= len + 1, 'newindex OOB')
  local sz = fi.sz
  if #v ~= sz then error(sfmt('failed to write %i bytes', #v)) end
  iseek(fi, i, 'w', sz); assert(fi.f:write(v))
  if i > len then fi.len = i end
  fi._i = i + 1
end
IFile.set = IFile.setbytes

--- Move the IFile's path to [$to].
---
--- [$mv] must be of type [$fn(from, to)]. If not provided,
--- [$civix.mv] will be used.
---
--- This can be done on both closed and opened files.
---
--- The IFile will re-open on the new file regardless of the
--- previous state.
IFile.move = function(fi, to, mvFn) --> fi
  assert(fi.path, 'cannot move tmp file')
  mvFn = mvFn or require'civix'.mv
  if fi.f then fi:flush(); fi:close() end
  mvFn(fi.path, to); fi.path = to
  fi.mode = 'r+'
  return fi:reload()
end

--- Get a new read-only instance with an independent file-descriptor.
---
--- Warning: currently the reader's len will be static, so this should
--- be mostly used for temporary cases. This might be changed in
--- the future.
IFile.reader = function(fi) --> IFile?, err?
  assert(fi.path, 'reader only allowed on file with path')
  fi:flush()
  local f,e = io.open(fi.path, 'r'); if not f then return nil, e end
  local r = ds.copy(fi)
  r.f, r.mode = f, 'r'
  return r
end

IFile.__fmt = function(fi, fmt)
  fmt:write('IFile(sz=', tostring(fi.sz), ' ')
  if fi.path then fmt:write(fi.path) end
  fmt:write')'
end

return IFile
