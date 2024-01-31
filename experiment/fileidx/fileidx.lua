local DOC = [[
Types for indexing data stored on disk.

Used to build minimalistic databases. For example, indexing TSO
data so it can be searched quickly.
]]

local pkg = require'pkg'
local mty = require'metaty'
local pack, unpack = string.pack, string.unpack

local M = {__doc = DOC}

local function __index(self, k)
  if type(k) == 'number' then return rawget(self, 'get')(k) end
  return assert(getmetatable(self)[k], 'unknown method')
end

local function readU8(f) return string.unpack('>U8', f:read(8)) end
local function writeU8(f, i8) f:write(string.pack('>U8', i8)) end

M.AscIndex = mty.doc[[
A simple index of ascending 64bit integers with a starting value.

Typically this has extension .64x
]](mty.record'indexers.AscU64Index')
  :field('file', 'userdata'):fdoc'file in mode=rb+ or wb+'
  :field('starti', 'number')
M.AscIndex.create = function(ty_, path, starti)
  local ai = M.AscIndex{
    file = mty.assertf(io.open(path, 'wb+'),
      'could not open path %q', path),
    starti = starti or 1,
  }
  ai:push(starti)
  return ai
end
M.AscIndex.open = function(ty_, path)
  local f = mty.assertf(io.open(path, 'rb+')
    'could not open path %q', path)
  return M.AscIndex{file = f, starti = readU8(f)}
end

M.AscIndex.__index = __index
M.AscIndex.get = function(ai, idx)
  assert(idx > 0, 'idx must be > 0')
  local pos = idx * 8
  assert(ai.f:seek('set', pos) == pos, 'idx out of range')
  return readU8(ai.f)
end
M.AscIndex.push = mty.doc[[push a position onto the AscIndex]]
(function(ai, pos) ai.f:seek'end'; writeU8(ai.f, pos) end)


return M
