local G = G or _G
--- civdb: minimalistic CRUD database
--- Use [$require'civdb.CivDB'] for the database object.
---
--- This module exports the encode/decode functions which
--- can be used for encoding and decoding plain-old-data.
local M = G.mod and mod'civdb' or setmetatable({}, {})
local S = require'civdb.sys'
local pod = require'ds.pod'

local encode, decode = S.encode, S.decode
local toPod, fromPod = pod.toPod, pod.fromPod

M.encode = function(val) return encode(toPod(val)) end --> string
M.decode = function(encoded, index--[[=1]]) --> value, encodedLen
  local v, elen = decode(encoded, index)
  return fromPod(v), elen
end

return M
