
local pkg = require'pkg'
local T   = pkg'civtest'
local M   = pkg'fd'
local aeq = T.assertEq

local p = '.out/fd.text'

T.test('open -> _write -> _read', function()
  local f = M.open(p, 'w'); aeq(0, f:code())
  f:_writepre'line 1\nline 2\n'
  aeq(0, f:_write())
  f:close()
  f = M.open(p, 'r'); aeq(0, f:code())
  aeq(0, f:_read())
  aeq('line 1\nline 2\n', f:_pop())
end)

T.test('read', function()
  local f = M.open(p, 'r'); aeq(0, f:code())
  aeq('line 1\nline 2\n', f:read()); aeq(14, f:pos())
  f:close()
end)

T.test('append', function()
  local f = M.open(p, 'a'); aeq(0, f:code())
  aeq(14, f:pos())
  f:write'line 3\n'; aeq(21, f:pos())
end)
