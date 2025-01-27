-- helpers for testing ele and related libraries
local M = mod and mod'ele.testing' or {}

local buffer = require'lines.buffer'
local eb = require'ele.bindings'
local Session = require'ele.Session'
local edit = require'ele.edit'

local push = table.insert

M.SLEEP = 0

M.newSession = function(text)
  local s = Session:test(); local ed = s.ed
  push(ed.buffers, buffer.Buffer.new(text))
  ed.edit = edit.Edit(nil, ed.buffers[1])
  return s
end

return M
