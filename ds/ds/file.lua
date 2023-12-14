
local mty = require'metaty'

local M = {}

M.LinesFile = mty.doc[[Read a file as if it were a lines table.

Dynamic creation:
  LinesFile(open'myfile.txt')
  LinesFile{open'myfile.txt', cache=10}
  LinesFile{file=open'myfile.txt', cache=10, len=myFileLen}

Performance is good as long as lookback is only within the cache length.

Also supports append line operations (len must be set).
]]
(mty.record'LinesFile')
  :field('file',       'userdata')
  :field('cache',      'number')
  :field('len',        'number')
  :field('_line',      'number')
  :field('cacheMiss',  'number')
:new(function(ty_, t)
  if t[1] then t.file = t[1]; t[1] = nil end
  t.cache, t.len = math.max(1, t.cache or 1), t.len or math.maxinteger
  t._line, t.cacheMiss = 0, 0
  return mty.new(ty_, t)
end)
M.LinesFile.__index = function(self, l)
  -- Note: only called if line is not already cached
  mty.assertf(l >= 1, 'line must be >= 1: %s', l)
  if l > self.len then return end
  if l < self._line then -- cache miss
    for i=math.min(1, self._line - self.cache + 1), self._line do
      rawset(self, i, nil)
    end
    self.file:seek'set'
    self._line, self.cacheMiss = 0, self.cacheMiss + 1
  end
  while self._line < l do
    local line = self.file:read'l'
    if not line then self.len = self._line; return end
    self._line = self._line + 1
    rawset(self, self._line, line)
    rawset(self, self._line - self.cache, nil)
  end
  return rawget(self, self._line)
end
M.LinesFile.__len = function(self)
  assert(self.len < math.maxinteger, 'len not set')
  return self.len
end

return M
