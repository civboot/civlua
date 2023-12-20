local mty = require'metaty'
local df  = require'ds.file'
local lua = require'pegl.lua'
local M = {}

M.LUCK = {
  sfmt=string.format, push=table.insert,

  string=string, table=table, utf8=utf8,
  type=type,   select=select,
  pairs=pairs, ipairs=ipairs, next=next,
  error=error, assert=assert,

  -- Note: cannot include math because of random
  abs=math.abs, ceil=math.ceil, floor=math.floor,
  max=math.max, min=math.min,
  maxinteger=math.maxinteger, tonumber=tonumber,

  __metatable = 'table',
}
M.LUCK.__index = function(e, i) return M.LUCK[i] end

M.load = function(dat, env)
  local i = 1
  local fn = function() -- alternates between next line and newline
    local o = '\n'; if i < 0 then i = 1 - i
    else  o = dat[i];             i =   - i end
    return o
  end
  local res = {}
  if env then setmetatable(res, env) else setmetatable(res, M.LUCK) end
  local e, err = load(fn, path, 'bt', res); if err then error(err) end
  e()
  mty.pnt(res)
  return res
end

M.luck = function(path)
  return M.load(df.LinesFile{io.open(path)})
end

return M
