
local pkg = require'pkg'
local T   = pkg'civtest'
local M   = pkg'fd'
local S   = M.sys
local aeq = T.assertEq
M.ioSync()

local p = '.out/fd.text'

T.test('open -> _write -> _read', function()
  local f = M.open(p, 'w'); aeq(0, f:code())
  f:_writepre'line 1\nline 2\n'
  aeq(0, f:_write())
  f:close()
  f = M.open(p, 'r'); aeq(0, f:code())
  aeq(S.FD_EOF, f:_read())
  aeq('line 1\nline 2\n', f:_pop())
  aeq('file', M.type(f))
  f:flush()
  f:close(); aeq('closed file', M.type(f))
end)

T.test('read', function()
  local f = M.open(p, 'r'); aeq(0, f:code())
  aeq('line 1\nline 2\n', f:read()); aeq(14, f:pos())
  f:close()
end)

T.test('read line', function()
  local f = M.open(p, 'r')
  aeq('line 1',   f:read'l')
  aeq('line 2\n', f:read'L')
  aeq(nil,        f:read'l')
  f:close()
end)

T.test('append', function()
  local f = M.open(p, 'a'); aeq(0, f:code())
  aeq(14, f:pos())
  f:write'line 3\n'; aeq(21, f:pos())
end)

local text = 'line 1\nline 2\nline 3\n'
T.lapTest('openFDT -> _read', function()
  local f = M.openFDT(p); aeq(M.FDT, getmetatable(f))
  aeq(0, f:code())
  f:_read(); while f:code() == S.FD_RUNNING do end
  aeq(S.FD_EOF, f:code())
  aeq(text, f:_pop())
  f:close()
end)

T.lapTest('FDT:read', function()
  local f = M.openFDT(p); aeq(text, f:read()); f:close()
end)

T.lapTest('FDT:lines', function()
  local f = M.openFDT(p)
  aeq('line 1',   f:read'l')
  aeq('line 2\n', f:read'L')
  aeq('line 3\n', f:read'L')
  aeq(nil,        f:read'l')
end)
