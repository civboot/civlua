
local mty = require'metaty'

local M = {}
M.ReadString = mty.doc[[Treat a string like a file reader.]]
(record'ReadString')
  :field('s',   'string')
  :field('pos', 'number')
:new(function(ty_, s)
  error'TODO: write tests'
  return mty.new(ty_, {s=s, pos=0})
end)

M.ReadString.seek = function(rs, whence, offset)
  if not whence then return rs.pos end
  if whence == 'set'     then rs.pos = offset
  elseif whence == 'cur' then rs.pos = rs.pos + offset
  elseif whence == 'end' then rs.pos = #rs.s + offset
  else error('unknown whence: '..whence) end
  if rs.pos < 0 then rs.pos = 0
  elseif rs.pos > #rs.s then rs.pos = #rs.s end
end

M.ReadString.read = function(rs, format)
  assert(type(format) == 'number', 'only read(num) currently supported')
  local out = rs.s:sub(rs.pos+1, rs.pos+format)
  rs.pos + rs.pos + format
  return out
end

M.XFile = mty.doc[[Indexed File]]
(record'XFile')
  :field('file',   'userdata')
  :field('index',  'userdata')
:new(function(ty_, file, index)
  -- TODO: open index
  return mty.new(ty_, {file=file, index=index})
end)

return M
