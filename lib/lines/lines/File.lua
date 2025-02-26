local mty = require'metaty'

--- (read|append)-only line based file (indexed and cached)
---
--- Note: use EdFile if you need to do non-append edits
---
--- Initialize with File{path=path?, mode=mode?}
local File = mty'File' {
  'path [string]', 'mode [string]',
  'f   [file]: open file',
  'idx [U3File]: line index of f',
  'cache [WeakV]: cache of lines',
  '_ln  [int]:  current line num (false=end)',
  '_pos [bool]: current file pos',
}

local fail = require'fail'
local ds = require'ds'
local pth = require'ds.path'
local lines = require'lines'
local U3File = require'lines.U3File'
local fd = require'fd'
local ix = require'civix'
local loadIdx = require'lines.futils'.loadIdx

local fassert, check, failed = fail.assert, fail.check, fail.failed
local trace = require'ds.log'.trace
local largs = lines.args
local push, concat = table.insert, table.concat
local getmt = getmetatable
local split, construct = mty.split, mty.construct
local index, newindex = mty.index, mty.newindex
local WeakV = ds.WeakV


File.IDX_DIR = pth.concat{pth.home(), '.data/lines'}

File._initnew = ds.noop -- empty file: do nothing
File._reindex = function(f, idx, l, pos)
  l, pos = l or 1, pos or 0
  if f:seek'end' == 0 then return end
  fassert(f:seek('set', pos))
  local lines = f:lines'L'
  local prev = lines()
  while true do
    idx[l] = pos; l = l + 1
    local line = lines(); if not line then break end
    pos, prev = pos + #prev, line
  end
  pos = pos + #prev
  if prev:sub(-1) == '\n' then
    idx[l] = pos
  end
  return pos
end

getmetatable(File).__call = function(T, t)
  t = t and assert(type(t) == 'table') and t or {}
  trace('%s.init%q', mty.tyName(T), t)
  local f, err, idx, fstat, xstat
  if not t.path then
    f, err   = check(io.tmpfile()); if failed(f) then return f end
    idx, err = U3File:create();     if failed(idx) then return idx end
    T._initnew(f, idx)
  elseif type(t.path) == 'string' then
    trace('reloading path %s', t.path)
    t.mode = t.mode or 'r'
    f, err = check(io.open(t.path, t.mode)); if failed(f) then return f end
    idx, err = loadIdx(f, pth.concat{T.IDX_DIR, t.path}, t.mode, T._reindex)
    if failed(idx) then return idx end
  else error'invalid path' end
  t.f, t.idx, t.cache = f, idx, WeakV{}
  return construct(T, t)
end

File.close = function(lf)
  if lf.idx then lf.idx:close()             end
  if lf.f   then lf.f:close(); lf.f = false end
end
File.flush = function(lf)
  local ok, err = lf.idx:flush(); if failed(ok) then return ok end
  ok, err = lf.f:flush()          if failed(ok) then return ok end
  local fstat, err = check(ix.stat(lf.f))
  if failed(fstat) then return fstat end
  return ix.setModified(lf.idx.f, fstat:modified())
end

--- append to file
File.write = function(lf, ...)
  local f, idx, cache, pos = lf.f, lf.idx, lf.cache
  local t = largs(...)
  local tlen = #t
  if tlen == 0 then return end
  if lf._ln or not lf._pos then
    pos = fassert(f:seek'end')
    lf._ln = false
  else pos = lf._pos end
  lf._pos = false
  fassert(f:write(t[1])); pos = pos + #t[1]
  local len = #idx -- start length
  if len == 0 then len = 1; idx[1] = 0 end
  cache[len] = nil
  for l=2,tlen do
    local line = t[l];
    fassert(f:write('\n', line));
    len = len + 1; idx[len] = pos + 1
    pos = pos + 1 + #line
  end
  lf._pos = pos
end

File.__len = function(lf) return #lf.idx end

getmetatable(File).__index = nil
File.__index = function(lf, i)
  if type(i) == 'string' then
    local mt = getmt(lf)
    return rawget(mt, i) or index(mt, i)
  end
  local cache = lf.cache
  local line = cache[i]; if line then return line end
  local f, idx, pos, err = lf.f, lf.idx, lf._pos
  if i > #idx then return end -- line num OOB
  if not pos or i ~= lf._ln then -- update file pos
    pos = assert(lf.idx[i])
    fassert(f:seek('set', pos))
  end
  line, err = f:read'L'; assert(not err, err)
  line = line or ''; lf._pos = pos + #line
  if line:sub(-1) == '\n' then line = line:sub(1, -2) end
  lf._ln, cache[i] = i + 1, line
  return line
end

File.__newindex = function(lf, i, v)
  if type(i) == 'string' then return newindex(lf, i, v) end
  local f, idx, cache, pos = lf.f, lf.idx, lf.cache, lf._pos
  local len = #idx; assert(i == len + 1, 'only append allowed')
  if not pos or lf._ln then pos = fassert(f:seek'end') end
  lf._ln, lf._pos = false, false
  if pos == 0 then
    fassert(f:write(v))
    lf._pos = pos + #v
  else
    fassert(f:write('\n', v))
    lf._pos = pos + #v + 1
    pos = pos + 1
  end
  idx[i], cache[i] = pos, v
end

File.__fmt = function(lf, fmt)
  push(fmt, 'lines.File(')
  if lf.path then push(fmt, lf.path) end
  push(fmt, ')')
end

File.reader = function(lf) --> lines.File (readonly)
  local idx, err = fassert(
    getmt(lf.idx):load(assert(lf.idx.path, 'idx path not set'), 'r'))
  local path = assert(lf.path, 'path not set')
  return construct(getmt(lf), {
    f=io.open(path, 'r'), path=path, cache=lf.cache, idx=idx,
  })
end

return File
