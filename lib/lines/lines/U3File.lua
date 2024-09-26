local mty = require'metaty'
--- A file that holds 3 byte (24 bit) integers. These are commonly
--- used for indexing lines.
---
--- This object supports get/set index operations including appending.
--- Every operation (except consecutive writes) requires a file seek.
local U3File = mty'lines.U3File' {
  'f     [file]', 'path  [string]',
  'len   [int]',  '_i [int]', -- len / current file index
}

local log = require'ds.log'
local mtype = math.type
local pack, unpack = string.pack, string.unpack
local sfmt = string.format

local index, newindex = mty.index, mty.newindex

--- seek to index. Invariant: [$i <= len+1]
local function iseek(u3, i)
  if u3._i == i then return end
  local to = (i-1) * 3
  local pos = assert(u3.f:seek('set', to))
  log.info('seek i=%s pos=%s -> got=%s (u3len=%s)', i, to, pos, #u3)
  assert(pos % 3 == 0, 'pos incorrect')
end

--- This creates a new index file at path (path=nil uses tmpfile()).
--- Note: Use load if you want to load an existing index.
U3File.create = function(T, path) --> U3File?, err
  local f, err; if path then f, err = io.open(path, 'w+')
  else                       f, err = io.tmpfile() end
  if not f then return f, err end
  return T{f=f, len=0, _i = 1, path=path}
end

--- reload from path
U3File.reload = function(u3, mode)
  local f, err = io.open(u3.path, mode or 'r+')
  if not f then return nil, err end
  local bytes = f:seek'end'
  f:seek('set', bytes - bytes % 3) -- truncate invalid bytes
  local len = bytes // 3
  u3.f, u3.len, u3._i = f, len, len
  return u3
end

--- load an index file
U3File.load = function(T, path, mode)
  return mty.construct(T, {path=path}):reload(mode)
end

U3File.flush   = function(u3) return u3.f:flush() end
U3File.__len   = function(u3) return u3.len       end
U3File.__pairs = ipairs

U3File.close = function(u3)
  if u3.f then u3.f:close(); u3.f = false end
end

U3File.__index = function(u3, k)
  if type(k) == 'string' then
    local mt = getmetatable(u3)
    return rawget(mt, k) or index(mt, k)
  end
  if k > u3.len then return end
  iseek(u3, k)
  local v = unpack('>I3', assert(u3.f:read(3)))
  u3._i = k + 1
  return v
end

U3File.__newindex = function(u3, k, v)
  if type(k) == 'string' then return newindex(u3, k, v) end
  local len = u3.len; assert(k <= len + 1, 'newindex OOB')
  local s = pack('>I3', v) -- pack first to throw errors
  iseek(u3, k)
  local _, err = u3.f:write(s); if err then error(err) end
  if k > len then u3.len = k end
  u3._i = k + 1
end

U3File.__fmt = function(u3, fmt)
  push(fmt, 'U3File(')
  if u3.path then push(fmt, u3.path) end
  push(fmt, ')')
end

return U3File
