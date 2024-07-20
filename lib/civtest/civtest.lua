local mty = require'metaty'
local ds = require'ds'
local lines = require'lines'

local add, sfmt = table.insert, string.format

local M = {}

-----------
-- Asserting

M.diffFmt = function(f, sE, sR)
  local linesE = lines(sE)
  local linesR = lines(sR)
  local l, c = lines.diff(linesE, linesR)
  mty.assertf(l and c, '%s, %s\n', l, c)
  add(f, sfmt("! Difference line=%q (", l))
  add(f, sfmt('lines[%q|%q]', #linesE, #linesR))
  add(f, sfmt(' strlen[%q|%q])\n', #sE, #sR))
  add(f, '! EXPECT: '); add(f, linesE[l] or '<empty>'); add(f, '\n')
  add(f, '! RESULT: '); add(f, linesR[l] or '<empty>'); add(f, '\n')
  add(f, string.rep(' ', c - 1 + 10))
  add(f, sfmt('^ (column %q)\n', c))
  add(f, '! END DIFF\n')
end

M.assertEq = function(expect, result, pretty)
  if mty.eq(expect, result) then return end
  local f = (pretty or pretty == nil) and mty.Fmt:pretty{}
          or mty.Fmt{}
  add(f, "! Values not equal:")
  add(f, "\n! EXPECT: "); f(expect)
  add(f, "\n! RESULT: "); f(result)
  add(f, '\n')
  if type(expect) == 'string' and type(result) == 'string' then
    M.diffFmt(f, expect, result)
  else
    local tyn = function(v) return mty.tyName(mty.ty(v)) end
    add(f, sfmt('! TYPES:  %s != %s',
                tyn(expect), tyn(result)))
  end
  error(table.concat(f))
end

M.assertErrorPat = function(errPat, fn, plain)
  local ok, err = pcall(fn)
  if ok then mty.errorf(
    'Did not recieve expected error.\n'
  ..'! Expected errPat %q\n! Got result[1]: %s',
    errPat, mty.tostring(err)
  )end
  if not err:find(errPat, 1, plain) then mty.errorf(
    '! Did not recieve expected error.\n'
  ..'! Expected errPat %q\n!### Got error:\n%q', errPat, err
  )end
end

M.assertMatch = function(expectPat, result)
  if not result:match(expectPat) then
    mty.errorf('Does not match pattern:\nPattern: %q\n Result:  %s',
           expectPat, result)
  end
end

M.assertGlobals = function(prevG)
  local newG = {}; for k in pairs(_G) do
    if prevG[k] == nil then add(newG, k) end
  end
  if #newG ~= 0 then error("New globals: "..mty.tostring(newG)) end
end

M.test = function(name, fn)
  local ge = ds.copy(_G)
  print('# Test', name)
  fn()
  M.assertGlobals(ge)
  collectgarbage()
end

-- Runs until yields non-truthy. See lib/lap/README.md
M.asyncTest = function(name, fn)
  local lap = require'lap'
  local civix = require'civix'
  local Lap = civix.Lap()
  local ge = ds.copy(_G)

  print('# Test', name, "(async)")
  Lap:run{fn}

  M.assertGlobals(ge)
  collectgarbage()
end

M.lapTest = function(name, fn)
  M.test(name, fn)
  M.asyncTest(name, fn)
end

return M
