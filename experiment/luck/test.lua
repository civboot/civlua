METATY_CHECK = true
local mty = require'metaty'
local ds = require'ds'
local T = require'civtest'
local LFile = require'lines.File'
local M = require'luck'
local D = 'lib/luck/'

T.meta = function()
  local path = D..'testdata/small.luck'
  local f = assert(LFile{path=path}); f.cache = ds.Forget{}
  local meta = M.loadMeta(f, path)
  T.eq({'small'}, meta)
  f:close()

  local path = D..'testdata/withdeps.luck'
  local f = assert(LFile{path=path}); f.cache = ds.Forget{}
  local meta = M.loadMeta(f, path)
  T.eq({
    'test.withdeps',
    deps = {
      vals = 'test.vals',
      small = 'small',
    }
  }, meta)
  f:close()
end

T.load = function()
  local smallPath = D..'testdata/small.luck'
  local valsPath  = D..'testdata/vals.luck'
  local res = M.load(smallPath)
  local small = {i=8, s="hello", t={1, 2, v=3}}
  T.eq(small, res)

  local res = M.loadall{D..'testdata/small.luck'}
  T.eq({small=small}, res)

  local resVals = M.load(valsPath)
  local vals = {val1 = 'first val', val2 = 222, val3 = 7}
  T.eq(vals, resVals)

  local withDeps = M.loadall{
    D..'testdata/withdeps.luck',
    smallPath, valsPath,
  }
  T.eq({
    small=small,
    ['test.vals'] = vals,
    ['test.withdeps'] = {
      gotVal1="got: first val",
      modVal1="only modified here, not test.vals",
      small = small,
      val2Plus3 = 229,
    }
  }, withDeps)
end

