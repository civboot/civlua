local G = G or _G

--- module for writing simple tests
local M = G.mod and G.mod'civtest' or {}

local mty = require'metaty'
local fmt = require'fmt'
local ds = require'ds'
local pth = require'ds.path'
local lines = require'lines'

local push, sfmt = table.insert, string.format
local function exit(rc) io.stderr:flush(); os.exit(rc) end

M.Test = (mty'Test'{})
M.Test.eq = function(a, b)
  if mty.eq(a, b) then return end
  local f = io.fmt
  f:styled('error', '\n!! EXPECTED:', '\n'); f(a)
  f:styled('error', '\n!! RESULT:', '\n');   f(b)
  if mty.ty(a) ~= mty.ty(b) then
    f:styled('error', '!! TYPES NOT EQUAL', ': ',
             mty.name(a), ' != ', mty.name(b), '\n')
  else
    if type(a) ~= 'string' then a, b = fmt.pretty(a), fmt.pretty(b) end
    if a == b then f:styled('notice', '\n(Formatted strings are equal)')
    else
      f:styled('error', '\n!! DIFF:', '\n')
      f(require'lines.diff'(a, b));
    end
  end
  f:styled('error', '\n!! Failed Test.eq:', ' ')
  f:styled('path', pth.nice(ds.srcloc(1)), '\n')
  exit(1)
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
  if not ok and err.msg:find(contains, 1, true) then return err end
  local f = io.fmt
  f:styled('error', '\n!! Unexpected Result:', '\n');
  if ok then f:styled('notice', '<no error>') else f(err) end
  f:styled('error', '\n!! Expected error to contain:',
           sfmt(' %q\n', contains))
  f:styled('error', '!! Failed Test.throws:', ' ')
  f:styled('path', pth.nice(ds.srcloc(1)), '\n')
  exit(1)
end
getmetatable(M.Test).__newindex = function(s, name, fn)
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

M.test = function(name, fn)
  print('# Test', name)
  fn()
  collectgarbage()
end

--- Runs until yields non-truthy. See lib/lap/README.md
M.asyncTest = function(name, fn)
  local lap = require'lap'
  local civix = require'civix'
  local Lap = civix.Lap()
  print('# Test', name, "(async)")
  local _, errors = Lap:run{fn}
  collectgarbage()
  if errors then error(fmt(errors)) end
end

M.lapTest = function(name, fn)
  M.test(name, fn)
  M.asyncTest(name, fn)
end

return M
