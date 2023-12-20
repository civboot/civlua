METATY_CHECK = true

local mty = require'metaty'
local test, assertEq, assertErrorPat; mty.lrequire'civtest'
local df  = require'ds.file'
local M = require'luck'

test("meta", function()
  local path = 'luck/testdata/withmeta.luck'
  local f = df.LinesFile{io.open(path), len=true}
  local meta = M.loadMeta(f, path)
  assertEq({'test.withmeta', deps = { vals = 'test.vals'} }, meta)
end)

test("small", function()
  local res = M.single('luck/testdata/small.luck')
  local expected = {i=8, s="hello", t={1, 2, v=3}}
  assertEq(expected, res)

  local res = M.load{'luck/testdata/small.luck'}
  assertEq({small=expected}, res)
end)

