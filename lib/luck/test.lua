METATY_CHECK = true
local pkg = require'pkg'
local mty = pkg'metaty'
local test, assertEq, assertErrorPat; pkg.auto'civtest'
local df  = pkg'ds.file'
local M = pkg'luck'
local D = 'lib/luck/'

test("meta", function()
  local path = D..'testdata/small.luck'
  local f = df.LinesFile{io.open(path), len=true}
  local meta = M.loadMeta(f, path)
  assertEq({'small'}, meta); f:close()

  local path = D..'testdata/withdeps.luck'
  local f = df.LinesFile{io.open(path), len=true}
  local meta = M.loadMeta(f, path)
  assertEq({
    'test.withdeps',
    deps = {
      vals = 'test.vals',
      small = 'small',
    }
  }, meta)
  f:close()
end)

test("load", function()
  local smallPath = D..'testdata/small.luck'
  local valsPath  = D..'testdata/vals.luck'
  local res = M.load(smallPath)
  local small = {i=8, s="hello", t={1, 2, v=3}}
  assertEq(small, res)

  local res = M.loadall{D..'testdata/small.luck'}
  assertEq({small=small}, res)

  local resVals = M.load(valsPath)
  local vals = {val1 = 'first val', val2 = 222, val3 = 7}
  assertEq(vals, resVals)

  local withDeps = M.loadall{
    D..'testdata/withdeps.luck',
    smallPath, valsPath,
  }
  assertEq({
    small=small,
    ['test.vals'] = vals,
    ['test.withdeps'] = {
      gotVal1="got: first val",
      modVal1="only modified here, not test.vals",
      small = small,
      val2Plus3 = 229,
    }
  }, withDeps)
end)

