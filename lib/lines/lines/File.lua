local mty = require'metaty'

-- (read|append)-only line based file (indexed and cached)
--
-- Note: use EdFile if you need to do non-append edits
local File = mty'File' {
  'f   [file]: open file', 'path [string]',
  'idx [U3File]: line index of f',
  'cache [WeakV]: cache of lines',
  '_ln  [int]:  current line num (false=end)',
  '_pos [bool]: current file pos',
}

local ds = require'ds'
local log = require'ds.log'
local lines = require'lines'
local U3File = require'lines.U3File'

local push, concat = table.insert, table.concat
local split, construct = mty.split, mty.construct
local index, newindex = mty.index, mty.newindex
local WeakV = ds.WeakV

-- reindex starting from from line 'l=1' and file 'pos=0'
local function reindex(f, idx, l, pos) --> endPos
  l = l or 1; pos = pos or 0; local last
  idx[l] = pos
  for line in f:lines'L' do
    l, pos = l + 1, pos + #line
    idx[l], last = pos, line
  end
  -- delete last index depending on whether ended with newline
  if not last or last:sub(-1) ~= '\n' then idx[l] = nil end
  return pos
end
getmetatable(File).reindex = reindex -- expose for testing

-- Create a new File at path (default idx=lines.U3File()).
File.create = function(T, path, idx) --> File
  local f, err; if path then f, err = io.open(path, 'w+')
                else         f, err = io.tmpfile() end
  if not f then return nil, err end
  if idx then assert(#idx == 0, 'idx must be empty')
  else
    idx, err = U3File:create()
    if not idx then return nil, err end
  end
  assert(f:seek'end')
  return construct(T, {f=f, path=path, idx=idx, cache=WeakV{}})
end

File.load = function(T, path, idx)
  local f, err = io.open(path, 'r+'); if not f   then return nil, err end
  if not idx then
    idx, err = U3File:create();       if not idx then return nil, err end
  end
  if #idx == 0 then reindex(f, idx) end
  return construct(T, {f=f, path=path, idx=idx, cache=WeakV{}})
end

File.tolist = function(lf) --> list
  local l = {}; for i, v in ipairs(lf) do l[i] = v end; return l
end

File.close = function(lf)
  lf.idx:close(); return lf.f:close()
end
File.flush = function(lf)
  lf.idx:flush(); return lf.f:flush()
end

-- append to file
File.write = function(lf, ...)
  local f, idx, cache, pos = lf.f, lf.idx, lf.cache
  local len = #idx -- start length
  local t = lines(concat{...}); local tlen = #t
  if tlen == 0 then return end
  if lf._ln or not lf._pos then
    pos = assert(f:seek'end')
    lf._ln = false
  else pos = lf._pos end
  lf._pos = false
  assert(f:write(t[1])); pos = pos + #t[1]
  cache[len] = nil
  for l=2,tlen do
    local line = t[l];
    assert(f:write('\n', line)); pos = pos + 1 + #line
    idx[len] = pos + 1
  end
  lf._pos = pos
end

File.__len = function(lf) return #lf.idx end

getmetatable(File).__index = nil
File.__index = function(lf, k)
  if type(k) == 'string' then
    local mt = getmetatable(lf)
    return rawget(mt, k) or index(mt, k)
  end
  local cache = lf.cache
  local line = cache[k]; if line then return line end
  local f, idx, pos = lf.f, lf.idx, lf._pos
  if k > #idx then return end -- line num OOB
  if not pos or k ~= lf._ln then -- update file pos
    pos = assert(lf.idx[k])
    assert(f:seek('set', pos))
  end
  local err
  line, err = f:read'L'; assert(not err, err)
  line = line or ''; lf._pos = pos + #line
  if line:sub(-1) == '\n' then line = line:sub(1, -2) end
  lf._ln, cache[k] = k + 1, line
  return line
end

File.__newindex = function(lf, k, v)
  if type(k) == 'string' then return newindex(lf, k, v) end
  local f, idx, cache, pos = lf.f, lf.idx, lf.cache, lf._pos
  local len = #idx; assert(k == len + 1, 'only append allowed')
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
  idx[k], cache[k], lf._ln = pos, v, false
end

File.__fmt = function(lf, fmt)
  push(fmt, 'lines.File(')
  if lf.path then push(fmt, lf.path) end
  push(fmt, ')')
end

return File
