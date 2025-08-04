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

local ds = require'ds'
local pth = require'ds.path'
local lines = require'lines'
local U3File = require'lines.U3File'
local fd = require'fd'
local ix = require'civix'
local loadIdx = require'lines.futils'.loadIdx

local trace = require'ds.log'.trace
local largs = lines.args
local push, concat = table.insert, table.concat
local getmt = getmetatable
local split, construct = mty.split, mty.construct
local index, newindex = mty.index, mty.newindex
local check, WeakV = ds.check, ds.WeakV
local get, set = ds.get, ds.set

getmetatable(File).__index = mty.hardIndex
File.__newindex            = mty.hardNewindex

File.IDX_DIR = pth.concat{pth.home(), '.data/lines'}

File._initnew = ds.noop -- empty file: do nothing
File._reindex = function(f, idx, l, pos) --!!> nil
  l, pos = l or 1, pos or 0
  if f:seek'end' == 0 then return end
  assert(f:seek('set', pos))
  local lines = f:lines'L'
  local prev = lines()
  while true do
    set(idx, l, pos); l = l + 1
    local line = lines(); if not line then break end
    pos, prev = pos + #prev, line
  end
  pos = pos + #prev
  if prev:sub(-1) == '\n' then
    set(idx, l, pos)
  end
  return pos
end

getmetatable(File).__call = function(T, t) --> File?, errmsg?
  t = t and assert(type(t) == 'table') and t or {}
  trace('%s.init%q', mty.tyName(T), t)
  local f, err, idx, fstat, xstat
  if not t.path then
    f, err   = io.tmpfile();    if not f   then return nil, err end
    idx, err = U3File:create(); if not idx then return nil, err end
    T._initnew(f, idx)
  elseif type(t.path) == 'string' then
    t.mode = t.mode or 'r'
    trace('reloading path %s %s', t.path, t.mode)
    f, err = io.open(t.path, t.mode); if not f then return nil, err end
    local ipath = pth.concat{T.IDX_DIR, t.path}
    idx, err = loadIdx(f, ipath, t.mode, T._reindex)
    if not idx then return nil, err end
  else error'invalid path' end
  t.f, t.idx, t.cache = f, idx, WeakV{}
  return construct(T, t)
end

File.close = function(lf)
  if lf.idx then lf.idx:close()             end
  if lf.f   then lf.f:close(); lf.f = false end
end
File.flush = function(lf) --> ok, errmsg?
  local o,e = lf.idx:flush(); if not o then return o,e end
  o,e = lf.f:flush()          if not o then return o,e end
  local fstat, e = ix.stat(lf.f)
  if not fstat then return nil,e end
  return ix.setModified(lf.idx.f, fstat:modified())
end

--- append to file
File.write = function(lf, ...) --> ok, errmsg?
  local f, idx, cache, pos, o,e = lf.f, lf.idx, lf.cache
  local t = largs(...)
  local tlen = #t
  if tlen == 0 then return end
  if lf._ln or not lf._pos then
    pos,e = f:seek'end'; if not pos then return pos,e end
    lf._ln = false
  else pos = lf._pos end
  lf._pos = false
  o,e = f:write(t[1]); if not o then return o,e end
  pos = pos + #t[1]
  local len = #idx -- start length
  if len == 0 then len = 1; idx:set(1, 0) end
  cache[len] = nil
  for l=2,tlen do
    local line = t[l];
    o,e = f:write('\n', line); if not o then return o,e end
    len = len + 1; idx:set(len, pos + 1)
    pos = pos + 1 + #line
  end
  lf._pos = pos
end

File.__len = function(lf) return #lf.idx end

--- Get line at index
File.get = function(lf, i) --> line
  local cache = lf.cache
  local line = cache[i]; if line then return line end
  local f, idx, pos, err = lf.f, lf.idx, lf._pos
  if i > #idx then return end -- line num OOB
  if not pos or i ~= lf._ln then -- update file pos
    pos = assert(lf.idx:get(i))
    assert(f:seek('set', pos))
  end
  line = check(2, f:read'L') or ''
  lf._pos = pos + #line
  if line:sub(-1) == '\n' then line = line:sub(1, -2) end
  lf._ln, cache[i] = i + 1, line
  return line
end

--- Set line at index
File.set = function(lf, i, v)
  local f, idx, cache, pos = lf.f, lf.idx, lf.cache, lf._pos
  local len = #idx; assert(i == len + 1, 'only append allowed')
  if not pos or lf._ln then pos = assert(f:seek'end') end
  lf._ln, lf._pos = false, false
  if pos == 0 then
    assert(f:write(v))
    lf._pos = pos + #v
  else
    assert(f:write('\n', v))
    lf._pos = pos + #v + 1
    pos = pos + 1
  end
  idx:set(i, pos); cache[i] = v
end

File.__fmt = function(lf, f)
  f:write'lines.File('
  if lf.path then f:write(lf.path) end
  f:write')'
end

File.reader = function(lf) --> lines.File (readonly)
  local path = assert(lf.path, 'path not set')
  local idx, err = assert(
    getmt(lf.idx):load(assert(lf.idx.path, 'idx path not set'), 'r'))
  return construct(getmt(lf), {
    f=assert(io.open(path, 'r')), path=path, cache=lf.cache, idx=idx,
  })
end

File.extend = ds.defaultExtend
File.icopy  = ds.defaultICopy

return File
