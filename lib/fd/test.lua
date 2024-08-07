local iotype = io.type

local T   = require'civtest'
local M   = require'fd'
local S   = M.sys
local aeq = T.assertEq
M.ioSync()

local p = '.out/fd.text'

T.test('bitops', function() -- just checking...
  aeq(0xFF00, 0xFFFF & (~0x00FF))
  aeq(0xF0F0, 0xFFFF & (~0x0F0F))
end)

T.test('open -> _write -> _read', function()
  local f = M.open(p, 'w'); aeq(0, f:code())
  aeq(0, f:_write'line 1\nline 2\n')
  f:close()
  f = M.open(p, 'r'); aeq(0, f:code())
  aeq(S.FD_EOF, f:_read())
  aeq('line 1\nline 2\n', f:_pop())
  aeq('file', M.type(f))
  f:flush()
  f:close(); aeq('closed file', M.type(f))
end)

T.lapTest('read', function()
  local f = M.open(p, 'r'); aeq(0, f:code())
  aeq('line 1\nline 2\n', f:read()); aeq(14, f:pos())
  f:close()
end)

T.lapTest('read line', function()
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
T.asyncTest('append', function()
  local f = M.open(p, 'a'); aeq(0, f:code())
  aeq(21, f:pos())
  f:write'line 4\n'; aeq(28, f:pos())
end)

local text = 'line 1\nline 2\nline 3\nline 4\n'
T.asyncTest('openFDT -> _read', function()
  local f = M.openFDT(p); aeq(M.FDT, getmetatable(f))
  aeq(0, f:code())
  f:_read(); while f:code() == S.FD_RUNNING do end
  aeq(S.FD_EOF, f:code())
  aeq(text, f:_pop())
  f:close()
end)

T.asyncTest('FDT:read', function()
  local f = M.openFDT(p); aeq(text, f:read()); f:close()
end)

T.asyncTest('FDT:lines', function()
  local f = M.openFDT(p)
  aeq('line 1',   f:read'l')
  aeq('line 2\n', f:read'L')
  aeq('line 3\n', f:read'L')
  aeq('line 4\n', f:read'L')
  aeq(nil,        f:read'l')
end)

T.test('fileno and friends', function()
  aeq(type(io.stderr), 'userdata')
  assert(iotype(io.stderr))
  aeq(0, M.fileno(io.stdin))
  aeq(2, M.fileno(io.stderr))
  aeq(false, M.isatty(io.tmpfile()))
  aeq(false, M.isatty(M.tmpfile()))
  aeq(true,  M.isatty(io.stderr))
  aeq(true,  M.isatty(2))

  aeq('chr', M.ftype(io.stdin))
  aeq('chr', M.ftype(io.stdout))
  aeq('file', M.ftype(io.tmpfile()))
  aeq('file', M.ftype( M.tmpfile()))
end)


local pipeTest = function(r, w)
  w:write'hi there'
  aeq('hi', r:read(2)); aeq(' there', r:read(6))
end
T.test('pipe', function() pipeTest(S.pipe()) end)
T.asyncTest('pipe', function()
  local r, w = S.pipe()
  pipeTest(r:toNonblock(), w:toNonblock())
  aeq(S.EWOULDBLOCK, r:_read(1))
  w:write'bye'
  aeq('b', r:read(1)); aeq('ye', r:read(2))
end)

