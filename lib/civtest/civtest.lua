local G = G or _G

--- module for writing simple tests
local M = G.mod and G.mod'civtest' or {}

local mty = require'metaty'
local fmt = require'fmt'
local fbin = require'fmt.binary'
local ds = require'ds'
local pth = require'ds.path'
local lines = require'lines'
local ix = require'civix'

local getmt = getmetatable
local push, sfmt = table.insert, string.format
local function exit(rc) io.stderr:flush(); os.exit(rc) end

local function errordiff(e, r)
  local f = io.fmt
  if e == r then return f:styled(
    'notice', '\n(Formatted strings are equal)'
  )end
  io.fmt:styled('error', '\n!! DIFF:', '\n')
  io.fmt(require'lines.diff'.Diff(e, r));
end
local function fail(name)
  error(sfmt('Failed %s', name), 2)
end

M.showDiff = function(f, a, b)
  f:styled('error', '\n!! RESULT:', '\n');   f(b)
  if mty.ty(a) ~= mty.ty(b) then
    f:styled('error', '\n!! TYPES:', ' ',
             mty.name(a), ' != ', mty.name(b), '\n')
  else
    if type(a) == 'string' then
      if #a ~= #b then f:styled('notify', sfmt(
        '\nLengths: %s ~= %s', #a, #b
      ))end
    else a, b = fmt.pretty(a), fmt.pretty(b) end
    errordiff(a, b)
  end
end
local showDiff = M.showDiff

--- Assert that [$a] equals [$b] (according to [<#metaty.eq>].
M.eq = function(a, b)
  if mty.eq(a, b) then return end
  showDiff(io.fmt, a, b); fail'Test.eq'
end

-- binary equal
M.binEq = function(e, r)
  assert(type(e) == 'string', 'expect must be string')
  assert(type(r) == 'string', 'result must be string')
  if e == r then return end
  if #e ~= #r then io.fmt:styled(
    'notify', sfmt('binary lengths: %s ~= %s\b', #e, #r)
  )end
  errordiff(fbin(e), fbin(r))
  fail'Test.binEq'
end

--- assert [$subj:find(pat)]
M.matches = function(pat, subj) --> !?error
  if subj:find(pat) then return end
  local f = io.fmt
  f:styled('error', '\n!! RESULT:', '\n');   f(subj)
  f:styled('error', '\n!! Did not match:', sfmt('%q\n', pat))
  f:styled('error', '!! Failed Test.matches:', ' ')
  f:styled('path', pth.nice(ds.srcloc(1)), '\n')
  fail'matches'
end

--- assert [$subj:find(pat, 1, true)] (plain find)
M.contains = function(plain, subj) --> !?error
  if subj:find(plain, 1, true) then return end
  io.fmt:styled('error', '\n!! RESULT:', '\n');   f(b)
  io.fmt:styled('error', '\n!! Did not contain:', sfmt('%q\n', plain))
  io.fmt:styled('error', '!! Failed Test.contains:', ' ')
  io.fmt:styled('path', pth.nice(ds.srcloc(1)), '\n')
  fail'contains'
end

--- assert [$fn()] fails and the [$contains] is in the message.
M.throws = function(contains, fn) --> ds.Error
  local ok, err = ds.try(fn)
  if ok then
    f:styled('error', '!! Unexpected: did not receive an error')
    fail'Test.throws (no error)'
  end
  if err.msg:find(contains, 1, true) then return err end
  local f = io.fmt
  f:styled('error', '\n!! Unexpected Result:', '\n');
  f:styled('error', 'Actual error:', '\n')
  f:write(err.msg)
  f:styled('error', '\n# end actual error', '\n')
  showDiff(io.fmt, contains, err.msg)
  fail'Test.throws (not expected)'
end

--- Assert that the path exists.
M.exists = function(path)
  if not require'civix'.exists(path) then error(
    'does not exist: '..path
  )end
end

--- Assert the contents at the two paths are equal
M.pathEq = function(a, b)
  local at, bt = pth.read(a), pth.read(b)
  if at == bt then return end
  showDiff(io.fmt, at, bt);
  io.fmt:styled('error', sfmt('Path expected: %s\n       result: %s',
    a, b), '\n')
  fail'Test.pathEq'
end

--- Assert that path matches expect. Expect can be of type:
--- * string: asserts the file contents match.
--- * table: recursively assert the subtree contents exist.
M.path = function(path, expect)
  M.exists(path)
  if type(expect) == 'string' then
    local txt = pth.read(path)
    if expect == txt then return end
    io.fmt:styled('error', '!! Path '..path, '\n')
    showDiff(io.fmt, expect, txt); fail'Test.tree'
  end
  if ix.pathtype(path) ~= ix.DIR then error(path..' is not a dir') end
  for k, v in pairs(expect) do M.path(pth.concat{path, k}, v) end
end

--- Test instance
--- This is typically the API for developing lua tests
--- (in civboot and elsewhere).
M.Test = (mty'Test'{
  'name [string]: the name of the test being run',
  'info [string]: additional test info to display per test',
  'runner [fn(testFn, Test)]: the test runner',
  'setup [list[fn]]: setup functions',
  'teardown [list[fn]]: teardown functions',
})
getmetatable(M.Test).__call = function(T, t)
  return mty.construct(T, t or {})
end
M.Test.eq       = M.eq
M.Test.binEq    = M.binEq
M.Test.exists   = M.exists
M.Test.pathEq   = M.pathEq
M.Test.path     = M.path
M.Test.matches  = M.matches
M.Test.contains = M.contains
M.Test.throws   = M.throws

M.Test.__newindex = function(s, name, fn)
  local mt = getmt(s)
  assert(not rawget(mt, name), name..' is a Test method')
  if rawget(mt.__fields, name) then
    return rawset(s, name, fn)
  end
  rawset(s, 'name', name)
  io.fmt:styled('h2', sfmt('## Test %-32s', name), ' ')
  if s.info then
    io.fmt:write'['
    io.fmt:styled('notify', s.info, '] ')
  end
  io.fmt:styled('path', pth.nice(select(2, mty.fninfo(fn))), '\n')
  if s.setup then
    for _, sfn in ipairs(s.setup) do sfn(s) end
  end
  if s.runner then s.runner(fn, s)
  else             fn(s) end
  if s.teardown then
    for _, tfn in ipairs(s.teardown) do tfn(s) end
  end
end
getmetatable(M.Test).__newindex = function()
  error'FIXME: remove me'
end

-----------------------
-- DEPRECATED

M.test = function(name, fn, path)
  print('# Test', name, pth.nice(path or ds.srcloc(1)))
  fn()
  collectgarbage()
end

--- Runs until yields non-truthy. See lib/lap/README.md
M.asyncTest = function(name, fn, path)
  local lap = require'lap'
  local civix = require'civix'
  local Lap = civix.Lap()
  print('# Test', name, "(async)", pth.nice(path or ds.srcloc(1)))
  local _, errors = Lap:run{fn}
  collectgarbage()
  if errors then error(fmt(errors)) end
end

M.lapTest = function(name, fn)
  local path = ds.srcloc(1)
  M.test(name, fn, path)
  M.asyncTest(name, fn, path)
end

return M
