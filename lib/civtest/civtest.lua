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

M.Test = (mty'Test'{})
M.Test.eq = function(a, b)
  if mty.eq(a, b) then return end
  showDiff(io.fmt, a, b); fail'Test.eq'
end

M.Test.exists = function(p)
  if not require'civix'.exists(p) then error(
    'does not exist: '..p
  )end
end

--- Assert the contents at the two paths are equal
M.Test.pathEq = function(a, b)
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
M.Test.path = function(path, expect)
  M.Test.exists(path)
  if type(expect) == 'string' then
    local txt = pth.read(path)
    if expect == txt then return end
    io.fmt:styled('error', '!! Path '..path, '\n')
    showDiff(io.fmt, expect, txt); fail'Test.tree'
  end
  if ix.pathtype(path) ~= ix.DIR then error(path..' is not a dir') end
  for k, v in pairs(expect) do M.Test.path(pth.concat{path, k}, v) end
end

-- binary equal
M.Test.binEq = function(e, r)
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
M.Test.matches = function(pat, subj) --> !?error
  if subj:find(pat) then return end
  f:styled('error', '\n!! RESULT:', '\n');   f(b)
  f:styled('error', '\n!! Did not match:', sfmt('%q\n', pat))
  f:styled('error', '!! Failed Test.matches:', ' ')
  f:styled('path', pth.nice(ds.srcloc(1)), '\n')
  exit(1)
end
--- assert [$subj:find(pat, 1, true)] (plain find)
M.Test.contains = function(plain, subj) --> !?error
  if subj:find(plain, 1, true) then return end
  io.fmt:styled('error', '\n!! RESULT:', '\n');   f(b)
  io.fmt:styled('error', '\n!! Did not contain:', sfmt('%q\n', plain))
  io.fmt:styled('error', '!! Failed Test.contains:', ' ')
  io.fmt:styled('path', pth.nice(ds.srcloc(1)), '\n')
  exit(1)
end
--- assert [$fn()] fails and the [$contains] is in the message.
M.Test.throws = function(contains, fn) --> ds.Error
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
getmetatable(M.Test).__newindex = function(s, name, fn)
  assert(not rawget(M.Test, name), name..' is a Test method')
  io.fmt:styled('h2', sfmt('## Test %-32s', name), ' ')
  io.fmt:styled('path', pth.nice(ds.srcloc(1)), '\n')
  fn(s)
end

-----------------------
-- DEPRECATED

--- simplest assertEq
M.assertEq = function(expect, result)
  if mty.eq(expect, result) then return end
  io.stderr:write('\n!! EXPECTED:\n', fmt(expect), '\n')
  io.stderr:write('\n!! RESULT:\n',   fmt(result), '\n')
  io.stderr:write('!! Failed assertEq: '..pth.nice(ds.srcloc(1)), '\n')
  exit(1)
end

M.assertErrorPat = function(errPat, fn, plain)
  local ok, err = pcall(fn)
  if ok then error(sfmt(
    'Did not recieve expected error.\n'
  ..'! Expected errPat %q\n! Got result[1]: %s',
    errPat, fmt(err)
  ))end
  if not err:find(errPat, 1, plain) then error(sfmt(
    '! Did not recieve expected error.\n'
  ..'! Expected errPat %q\n!### Got error:\n%q', errPat, err
  ))end
end

M.assertMatch = function(expectPat, result)
  if not result:match(expectPat) then
    fmt.errorf('Does not match pattern:\nPattern: %q\n Result:  %s',
           expectPat, result)
  end
end

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
