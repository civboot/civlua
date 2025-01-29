local G = G or _G
local M = G.mod and mod'ds.testing_pod' or {}

local T  = require'civtest'.Test
local ds = require'ds'
local fmt = require'fmt'

--- Test [$eq(v, decFn(encFn(v))]
--- If expectEncoding is provided then test [$eq(expectEncoding, encFn(v)]
M.round = function(v, encFn, decFn, expectEncoding) --> (enc, dec)
  local enc = encFn(v)
  if expectEncoding ~= nil then
    T.binEq(expectEncoding, enc)
  end
  local dec = decFn(enc)
  T.eq(v, dec)
  return enc, dec
end
M.roundList = function(values, encFn, decFn)
  for _, v in ipairs(values) do
    local ok, err = ds.try(M.round, v, encFn, decFn)
    if not ok then
      fmt.errorf('for value:\n%q\ngot: %s', v, err)
    end
  end
end

M.BOOLS = { false, true, }
M.INTS = {
  0, 1, 2, 10, 0xFF,   0x100,  0xFFFF,
    -1,   -10, -0xFF, -0x100, -0xFFFF,
}
M.STRINGS = {
  'a', 'abc', '01234', 'A0B1',
  '🚀rocket🚀',
}
M.BYTES = {
  'zero\x00okay', 'ff\xFFokay',
}
M.LISTS = {
  {},
  {0}, {'0'},
  M.BOOLS,
  M.STRINGS,
  M.BYTES,
  ds.flatten(M.BOOLS, M.STRINGS, M.BYTES),
}

M.MAPS = {
  {a=1}, {akey='akeyval', bkey='bkeyval'},
  {[4]='1num', [7]='7num'},
  {table = {innerkey='inner value'}},
  {bools = M.BOOLS},
  {ints = M.INTS},
  {strings = M.STRINGS},
  {lists = M.LISTS},
}

M.TABLES = {
  {'one', 'two', 'three', key='value'},
}

M.BUILTIN = ds.flatten(M.BOOLS, M.STRINGS, M.BYTES, M.LISTS, M.MAPS, M.TABLES)

M.testAll = function(...)
  M.roundList(M.BUILTIN, ...)
end

return M
