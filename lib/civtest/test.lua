
local mty = require'metaty'
local ds  = require'ds'
local CT = require'civtest'
local T = CT.Test()

T.civtest = function()
  T.eq(1, 1)
  T.eq('hi', 'hi')
  T.eq({1, 2, a=5}, {1, 2, a=5})
  T.throws('hi there', function() error('hi there bob') end)
end

T.global = function()
  G.testGlobal = true; assert(testGlobal)
  testGlobal = nil;    assert(nil == G.testGlobal)
  T.throws('global someGlobal is nil/unset', function()
    someGlobal = true
  end)
  assert(G.someGlobal == nil)
end

CT.asyncTest('foo', function()
  assert(true)
end)
