-- TODO: a lot of this should be moved to lines module
-- Lines-like file objects which you can use with lines.
-- 
-- These objects support only append-line mutations using table.insert.
local M = mod and mod'ds.file' or {}

local mty = require'metaty'
local ds  = require'ds'

local function idxLen(f)
  local len = f:seek'end'
  mty.assertf(len % 3 == 0, 'invalid idx len, not div by 3: %s', len)
  return len // 3
end

-- read the number of lines of a file.
-- 
-- If you pass a file object in, it is your job to pre-seek to zero
-- and then appropriately deal with the file object.
M.readLen = function(f)
  local len = 0; if type(f) == 'string' then
    for _ in io.lines(f, 'l') do len = len + 1 end
  else
    for _ in f:lines'l'       do len = len + 1 end
  end
  return len
end

-----------------------------------
-- LinesFile

-- Read and append to a file as if it were a lines table.
--
-- Dynamic creation:
--   LinesFile(io.open'myfile.txt')
--   LinesFile{io.open'myfile.txt', cache=10}
--   LinesFile {
--     io.open'myfile.txt',
--     len=ds.file.readLen'myfile.txt',
--     cache=10,
--   }
--   LinesFile:appendTo'someFile.log'
-- 
-- Performance is good as long as lookback is only within the cache length.  You
-- can assert on the cacheMiss in tests/etc to ensure you have the correct cache
-- settings.
M.LinesFile = mty'LinesFile'{
  'file      [file]',
  'cache     [int]',
  'len       [int]',
  'cacheMiss [int]',
  '_line     [int]',
  '_pos      [int]',
}
getmetatable(M.LinesFile).__call = function(T, t)
  if t[1] then t.file = t[1]; t[1] = nil end
  t.cache, t.len = math.max(1, t.cache or 1), t.len or math.maxinteger
  if t.len == true then
    t.file:seek'set'; t.len = M.readLen(t.file); t.file:seek'set'
  end
  t.cacheMiss, t._line, t._pos = 0, 0, -1
  return mty.construct(T, t)
end

-- Append to file at path.
-- 
-- performance: unless you specify the len this will first read the entire file to
-- find the length.
-- 
-- Example:
--   LinesFile:appendTo'file.txt'
--   LinesFile:appendTo{'file.txt', cache=10, len=fileLen}
M.LinesFile.appendTo = function(ty_, t)
  if type(t) == 'string' then t = {t} end
  assert(not t.file, 'specify path as first index')
  local path = t[1]; assert(path, 'need path')
  t[1] = io.open(path, 'a+')
  if not t.len then
    t.len = M.readLen(t[1]); t[1]:seek'set'
  end
  return M.LinesFile(t)
end
M.LinesFile.__index = function(self, l)
  local meth = getmetatable(self)[l]; if meth then return meth end
  -- Note: only called if line is not already cached
  mty.assertf(l >= 1, 'line must be >= 1: %s', l)
  if l > self.len    then return                end
  if l < self._line  then self:clearCache(true) end
  if self._line == 0 then self._pos = 0         end
  if self._pos  >= 0 then
    self.file:seek('set', self._pos)
    self._pos = -1
  end
  while self._line < l do
    local line = self.file:read'l'
    if not line then self.len = self._line; return end
    self._line = self._line + 1
    rawset(self, self._line,              line)
    rawset(self, self._line - self.cache, nil)
  end
  return rawget(self, self._line)
end
M.LinesFile.clearCache = function(self, isMiss)
  if self._line == 0 then return end
  if isMiss then self.cacheMiss = self.cacheMiss + 1 end
  for i=math.min(1, self._line - self.cache + 1), self._line do
    rawset(self, i, nil)
  end
  self._line = 0
end
M.LinesFile.__newindex = function(self, l, line)
  assert(len ~= math.maxinteger, 'must set len for append')
  mty.assertf(l == self.len + 1,
    'only append supported. len=%s l=%s', self.len, l)
  assert(not line:match'\n', 'cannot have newlines in line')
  if self._pos < 0 then self._pos = self.file:seek'cur' end
  self.len = self.len + 1
  self.file:write(line, '\n')
end
M.LinesFile.__len = function(self)
  assert(self.len < math.maxinteger, 'missing len')
  return self.len
end
M.LinesFile.flush = function(self) return self.file:flush() end
M.LinesFile.close = function(self) return self.file:close() end

-----------------------------------
-- IndexedFile and FileIdx

-- A file that holds file-position of lines in another file.
M.FileIdx = mty'FileIdx' {
  'file  [userdata]',
  'len   [number]',
  '_line [number]',
}
getmetatable(M.FileIdx).__call = function(T, t)
  if not t.len then t.len = idxLen(t.file) end
  t._line = 0
  return mty.construct(T, t)
end

-- Args:
--   file: path or file object (update mode)
--   idxpath: (optional) path to idx file. default=io.tmpfile()
--   preserve: if true, the index at idxpath will be preserved
--     and updated.
--
-- Returns: FileIdx for use with lines.IndexedFile or other places indexes are
-- needed.
M.FileIdx.create = function(T, file, idxpath, preserve)
  file = (type(file) == 'string') and io.open(file) or file
  local idx = idxpath and io.open(idxpath, preserve and 'r+' or 'w+')
            or io.tmpfile()
  local fidx = M.FileIdx{file=idx}
  local pos, lastPos = 0, file:seek'end'
  if fidx.len > 0 then
    file:seek('set', fidx:getPos(fidx.len))
    file:read'l' -- skip already indexed line
    pos = file:seek'cur'
  else file:seek'set' end -- start at beginning
  while pos ~= lastPos do
    fidx:addPos(pos)
    file:read'l'
    pos = file:seek'cur'
  end
  return fidx
end

M.FileIdx.getPos = function(self, l)
  mty.assertf(l > 0 and l <= self.len,
    "Line %s OOB (len=%s)", l, self.len)
  if l ~= self._line then
    self.file:seek('set', (l - 1) * 3)
  end
  self._line = l + 1
  return string.unpack('>I3', self.file:read(3))
end
M.FileIdx.addPos = function(self, pos)
  if self._line > 0 then
    self._line = 0
    self.file:seek'end'
  end
  self.file:write(string.pack('>I3', pos))
  self.len = self.len + 1
end
M.FileIdx.flush = function(self) return self.file:flush() end
M.FileIdx.close = function(self) return self.file:close() end

-- Lines-like File backed by a index.
-- 
-- This makes lookup O(1), though every line lookup requires one or more file
-- reads (you may want to use with a cache).
-- 
-- IndexedFile{path}                  -- tmpfile index
-- IndexedFile{path, idx=pathToIndex} -- load index from pathToIndex
M.IndexedFile = mty'IndexedFile' {
  'file   [userdata]',
  'idx    [FileIdx]',
  '_line  [number]',
  '_cache [WeakV]: cache of lines',
  '_seeks [int]: count of seeks performed',
}
getmetatable(M.IndexedFile).__call = function(T, t)
  if t[1] then t.file = t[1]; t[1] = nil end
  if mty.ty(t.idx) ~= M.FileIdx then
    t.idx = M.FileIdx:create(t.file, t.idx, true)
  end
  t._line, t._cache, t._seeks = 0, ds.WeakV{}, 0
  return mty.construct(T, t)
end
M.IndexedFile.__index = function(self, l)
  if type(l) == 'string' then
    return getmetatable(self)[l] or error('no method: '..l)
  end
  if l < 1 or l > self.idx.len then return end
  local line = self._cache[l]; if line then return line end
  if l ~= self._line then
    self._seeks = self._seeks + 1
    self.file:seek('set', self.idx:getPos(l))
  end
  line = assert(self.file:read'l'); self._cache[l] = line
  self._line = l + 1
  return line
end
M.IndexedFile.__newindex = function(self, l, line)
  mty.assertf(l == self.idx.len + 1,
    "Only append allowed. l=%s len=%s", l, self.idx.len)
  if self._line ~= l + 1 then
    self._seeks = self._seeks + 1
    self.idx:addPos(self.file:seek'end')
  end
  self.file:write(line, '\n')
  self._cache[l] = line
  self._line = l + 1
end
M.IndexedFile.__len = function(self) return self.idx.len end
M.IndexedFile.flush = function(self)
  self.file:flush()
  self.idx:flush()
end
M.IndexedFile.close = function(self)
  self.idx:close()
  return self.file:close()
end
M.IndexedFile.__close = M.IndexedFile.close

return M
