local mty = require'metaty'
local ds = require'ds'

local add, sfmt = table.insert, string.format

local M = {}

-----------
-- Asserting

M.diffFmt = function(f, sE, sR)
  local linesE = ds.lines(sE)
  local linesR = ds.lines(sR)
  local l, c = ds.lines.diff(linesE, linesR)
  mty.assertf(l and c, '%s, %s\n', l, c)
  add(f, sfmt("! Difference line=%q (", l))
  add(f, sfmt('lines[%q|%q]', #linesE, #linesR))
  add(f, sfmt(' strlen[%q|%q])\n', #sE, #sR))
  add(f, '! EXPECT: '); add(f, linesE[l] or '<empty>'); add(f, '\n')
  add(f, '! RESULT: '); add(f, linesR[l] or '<epmty>'); add(f, '\n')
  add(f, string.rep(' ', c - 1 + 10))
  add(f, sfmt('^ (column %q)\n', c))
  add(f, '! END DIFF\n')
end

M.assertEq = function(expect, result, pretty)
  if mty.eq(expect, result) then return end
  local f = (pretty or pretty == nil) and mty.Fmt2:pretty{}
          or mty.Fmt2{}
  add(f, "! Values not equal:")
  add(f, "\n! EXPECT: "); f(expect)
  add(f, "\n! RESULT: "); f(result)
  add(f, '\n')
  if type(expect) == 'string' and type(result) == 'string' then
    M.diffFmt(f, expect, result)
  end
  error(table.concat(f))
end

M.assertErrorPat = function(errPat, fn, plain)
  local ok, err = pcall(fn)
  if ok then mty.errorf(
    '! No error received, expected: %q', errPat
  )end
  if not err:find(errPat, 1, plain) then mty.errorf(
    '! Expected error:\n%q\n!### Got error:\n%q', errPat, err
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
end

-- Runs until yields non-truthy. See lib/lap/README.md
M.lapTest = function(name, fn)
  local ge = ds.copy(_G)
  print('# Test', name, "(lap)")
  local cor = coroutine.create(fn)
  while true do
    local ok, res = coroutine.resume(cor)
    if not ok then
      error(table.concat{
        'Coroutine error: ', debug.traceback(cor, res), '\n',
        'Error in lapTest',
      })
    end
    if not res then break end
  end
  M.assertGlobals(ge)
end

-- Globally require a module. ONLY FOR TESTS.
M.grequire = function(mod)
  if type(mod) == 'string' then mod = require(mod) end
  for k, v in pairs(mod) do
    mty.assertf(not _G[k], '%s already global', k); _G[k] = v
  end
  return mod
end

return M
