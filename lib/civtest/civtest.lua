local G = G or _G

--- module for writing simple tests
local M = G.mod and G.mod'civtest' or setmetatable({}, {})
M.SUBNAME = ''

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

--- Run the test, printing information to the terminal.
---
--- This function computes name=[$name..civtest.SUBNAME]
--- and sets civtest.NAME to the new name, which can be
--- used in the test.
---
--- ["Note: normally this is called when the user sets
---   a key to the civtest module, which has __newindex()
---   overriden to call this function.
--- ]
M.runTest = function(name, fn, path)
  name = name..M.SUBNAME
  rawset(M, 'NAME', name);
  io.fmt:styled('h2', sfmt('## Test %-32s', name), ' ')
  io.fmt:styled('path', pth.nice(path), '\n')
  return fn()
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
    io.fmt:styled('error',
      '!! Unexpected: did not receive an error')
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

getmetatable(M).__newindex = function(m, name, fn)
  return m.runTest(name, fn, select(2, mty.fninfo(fn)))
end
return M
