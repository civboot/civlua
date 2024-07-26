-- LFile: the magic lines file.
local M = mod and mod'lines.lfile' or {}

local mty = require'metaty'
local ds = require'ds'
local max = math.max

M.Slice = mty'FSlice' {
  'si [int]: start index',
  'ei [int]: end index',
}
M.Slice.__len = function(s) return s.ei - s.si + 1 end

-- return either one or two FSlices, the first one always to the left
-- returns new slice if they are merged.
M.Slice.merge  = function(a, b) --> first, second?
  if a.si > b.si then a, b = b, a end -- fix ordering
  if a.ei < b.si then return a, b end
  return M.FSlice{si=a.si, ei=max(a.ei, b.ei)}
end

-- A file-backed lines object which also acts as a file interface
-- which only supports write (append) and not seek.
M.File = mty'File' {
  'f   [file]: open file', 'path [string]',
  'idx [U3File]: line index',
  'dat [ds.ll]: linked-list of Slice|Gap',
  '_pos [int]',
}

M.File.create = function(T, path, mode)

end


return M
