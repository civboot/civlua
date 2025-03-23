local iotype = io.type

local T   = require'civtest'.Test()
local CT = require'civtest'
local M   = require'fd'
local ds = require'ds'
local S   = M.sys
local aeq = T.eq
M.ioSync()

local p = '.out/fd.text'

T.bitops = function()
  aeq(0xFF00, 0xFFFF & (~0x00FF))
  aeq(0xF0F0, 0xFFFF & (~0x0F0F))
end

T['open -> _write -> _read'] = function()
  local f = M.open(p, 'w'); aeq(0, f:code())
  print'opened'
  aeq(0, f:_write'line 1\nline 2\n'); print'wrote lines'
  f:close(); print'closed'
  f = M.open(p, 'r'); aeq(0, f:code()) print'opened'
  aeq(S.FD_EOF, f:_read()) print'read EOF'
  aeq('line 1\nline 2\n', f:_pop())
  aeq('file', M.type(f)); print'got type'
  f:flush();              print'flushed'
  f:close(); aeq('closed file', M.type(f))
end

-- FIXME
-- CT.lapTest('read', function()
--   local f = M.open(p, 'r'); aeq(0, f:code())
--   aeq('line 1\nline 2\n', f:read'a'); aeq(14, f:pos())
--   f:close()
-- end)
-- 
-- 
-- CT.lapTest('read line', function()
--   local f = M.open(p, 'r')
--   aeq('line 1',   f:read'l')
--   aeq('line 2\n', f:read'L')
--   aeq(nil,        f:read'l')
--   f:close()
-- end)
-- 
T.append = function()
  local f = M.open(p, 'a'); aeq(0, f:code())
  aeq(14, f:pos())
  f:write'line 3\n'; aeq(21, f:pos())
end

-- FIXME
-- CT.asyncTest('append', function()
--   local f = M.open(p, 'a'); aeq(0, f:code())
--   aeq(21, f:pos())
--   f:write'line 4\n'; aeq(28, f:pos())
-- end)
-- 
-- local text = 'line 1\nline 2\nline 3\nline 4\n'
-- CT.asyncTest('openFDT -> _read', function()
--   local f = M.openFDT(p); aeq(M.FDT, getmetatable(f))
--   aeq(0, f:code())
--   f:_read(); while f:code() == S.FD_RUNNING do end
--   aeq(S.FD_EOF, f:code())
--   aeq(text, f:_pop())
--   f:close()
-- end)
-- 
-- CT.asyncTest('FDT:read', function()
--   local f = M.openFDT(p); aeq(text, f:read'a'); f:close()
-- end)
-- 
-- CT.asyncTest('FDT:lines', function()
--   local f = M.openFDT(p)
--   aeq('line 1',   f:read'l')
--   aeq('line 2\n', f:read'L')
--   aeq('line 3\n', f:read'L')
--   aeq('line 4\n', f:read'L')
--   aeq(nil,        f:read'l')
-- end)

T['fileno and friends'] = function()
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
end

local pipeTest = function(r, w)
  w:write'hi there'
  aeq('hi', r:read(2)); aeq(' there', r:read(6))
end
T.pip = function() pipeTest(S.pipe()) end
CT.asyncTest('pipe', function()
  local r, w = S.pipe()
  pipeTest(r:toNonblock(), w:toNonblock())
  aeq(S.EWOULDBLOCK, r:_read(1))
  w:write'bye'
  aeq('b', r:read(1)); aeq('ye', r:read(2))
end)

--- testFn(openFn) is called with both file types.
local allFileTest = function(testFn)
  testFn(M.io.open)
  testFn(M.open)
end

--- check that both files behave the same
T.checkBoth = function() allFileTest(function(open)
  local f = open(p, 'w+')
  f:write'hello!'
    -- TODO: try read'a' here for odd results
    T.eq(nil, f:read());
    T.eq(6, f:seek'cur')

  T.eq(0, f:seek'set')
    T.eq('hello!', f:read'a')
    T.eq(6, f:seek'cur')
    T.eq(nil, f:read())
    T.eq('',  f:read'a')

  T.eq(3, f:seek('set', 3))
    T.eq('lo!', f:read(3))
    T.eq(6, f:seek'cur'); T.eq(nil, f:read()) -- TODO: read'a' is weird here

  T.eq(0, f:seek'set');
    T.eq('hel', f:read(3)); T.eq(3, f:seek'cur')
    T.eq('lo!', f:read(3)); T.eq(6, f:seek'cur')
    T.eq('',  f:read'a')
    T.eq(nil, f:read())
end) end


-- Note: most test coverage is in things that
-- use IFile (i.e. U3File).
T.IFile = function()
  local IFile = require'fd.IFile'
  local fi = IFile:create(1)
  ds.extend(fi, {'a', 'b', 'c'})
  T.eq({'a', 'b', 'c'}, ds.icopy(fi))
  fi[2] = 'B'
  T.eq({'a', 'B', 'c'}, ds.icopy(fi))

  local fi = IFile:create(2)
  ds.extend(fi, {'aa', 'bb', 'cc'})
  T.eq({'aa', 'bb', 'cc'}, ds.icopy(fi))
end

