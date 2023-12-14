
local mty = require'metaty'

local M = {}

M.readLen = mty.doc[[read the number of lines of a file.

If you pass a file object in, it is your job to seek or
close the file appropriately when done.
]](function(f)
  local len = 0; if type(f) == 'string' then
    for _ in io.lines(f, 'l') do len = len + 1 end
  else
    for _ in f:lines'l'       do len = len + 1 end
  end
  return len
end)

M.LinesFile = mty.doc[[
Read and append to a file as if it were a lines table.

Dynamic creation:
  LinesFile(io.open'myfile.txt')
  LinesFile{io.open'myfile.txt', cache=10}
  LinesFile {
    io.open'myfile.txt',
    len=ds.file.readLen'myfile.txt',
    cache=10,
  }
  LinesFile:appendTo'someFile.log'

Performance is good as long as lookback is only within the cache length.
]]
(mty.record'LinesFile')
  :field('file',        'userdata')
  :field('cache',         'number')
  :field('len',           'number')
  :field('cacheMiss',     'number')
  :field('_line',         'number')
  :field('_pos',          'number')
:new(function(ty_, t)
  if t[1] then t.file = t[1]; t[1] = nil end
  t.cache, t.len = math.max(1, t.cache or 1), t.len or math.maxinteger
  t.cacheMiss, t._line, t._pos = 0, 0, -1
  return mty.new(ty_, t)
end)

M.LinesFile.appendTo = mty.doc[[
Append to file at path.

performance: unless you specify the len this will first read the entire file to
find the length.

Example:
  LinesFile:appendTo'file.txt'
  LinesFile:appendTo{'file.txt', cache=10, len=fileLen}
]](function(ty_, t)
  if type(t) == 'string' then t = {t} end
  assert(not t.file, 'specify path as first index')
  local path = t[1]; assert(path, 'need path')
  t[1] = io.open(path, 'a+')
  if not t.len then
    t.len = M.readLen(t[1]); t[1]:seek'set'
  end
  return M.LinesFile(t)
end)

M.LinesFile.__index = function(self, l)
  local meth = getmetatable(self)[l]; if meth then return meth end
  mty.pntf('?? index=%s len=%s, pos=%s', l, self.len, self._pos)
  -- Note: only called if line is not already cached
  mty.assertf(l >= 1, 'line must be >= 1: %s', l)
  if l > self.len    then return                end
  if l < self._line  then self:clearCache(true) end
  if self._line == 0 then self._pos = 0         end
  if self._pos  >= 0 then
    mty.pnt('?? seeking', self._pos)
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
  self.len = self.len + 1
  if self._pos < 0 then self._pos = self.file:seek'cur' end
  mty.pntf('?? writing: %q', line)
  self.file:write(line, '\n')
end
M.LinesFile.__len = function(self)
  assert(self.len < math.maxinteger, 'missing len')
  return self.len
end
M.LinesFile.flush = function(self) return self.file:flush() end
M.LinesFile.close = function(self) return self.file:close() end

return M
