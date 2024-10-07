local G = G or _G

--- module for writing simple tests
local M = G.mod and G.mod'civtest' or {}

local mty = require'metaty'
local fmt = require'fmt'
local ds = require'ds'
local lines = require'lines'

local push, sfmt = table.insert, string.format

-----------
-- Asserting

-- simple diff algorithm... this can probably be improved
local matches = function(s, m)
  local out = {}; for v in string.gmatch(s, m) do
    push(out, v) end
  return out
end
local explode = function(s) return matches(s, '.') end
local diffCol = function(sL, sR)
  local i, sL, sR = 1, explode(sL), explode(sR)
  while i <= #sL and i <= #sR do
    if sL[i] ~= sR[i] then return i end
    i = i + 1
  end
  if #sL < #sR then return #sL + 1 end
  if #sR < #sL then return #sR + 1 end
  return nil
end
local diff = function(linesL, linesR)
  local i = 1
  while i <= #linesL and i <= #linesR do
    local lL, lR = linesL[i], linesR[i]
    if lL ~= lR then
      return i, assert(diffCol(lL, lR))
    end
    i = i + 1
  end
  if #linesL < #linesR then return #linesL + 1, 1 end
  if #linesR < #linesL then return #linesR + 1, 1 end
  return nil
end

M.diffFmt = function(f, sE, sR)
  local linesE = lines(sE)
  local linesR = lines(sR)
  local l, c = diff(linesE, linesR)
  fmt.assertf(l and c, '%s, %s\n', l, c)
  push(f, sfmt("! Difference line=%q (", l))
  push(f, sfmt('lines[%q|%q]', #linesE, #linesR))
  push(f, sfmt(' strlen[%q|%q])\n', #sE, #sR))
  push(f, '! EXPECT: '); push(f, linesE[l] or '<empty>'); push(f, '\n')
  push(f, '! RESULT: '); push(f, linesR[l] or '<empty>'); push(f, '\n')
  push(f, string.rep(' ', c - 1 + 10))
  push(f, sfmt('^ (column %q)\n', c))
  push(f, '! END DIFF\n')
end

M.assertEq = function(expect, result, pretty)
  if mty.eq(expect, result) then return end
  local f = (pretty or pretty == nil) and fmt.Fmt:pretty{}
          or fmt.Fmt{}
  push(f, "! Values not equal:")
  push(f, "\n! EXPECT: "); f(expect)
  push(f, "\n! RESULT: "); f(result)
  push(f, '\n')
  if type(expect) == 'string' and type(result) == 'string' then
    M.diffFmt(f, expect, result)
  elseif mty.ty(expect) ~= mty.ty(result) then
    local tyn = function(v) return mty.tyName(mty.ty(v)) end
    push(f, sfmt('! TYPES:  %s != %s',
                 tyn(expect), tyn(result)))
  end
  error(table.concat(f))
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
