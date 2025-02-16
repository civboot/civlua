
local T = require'civtest'.Test

local pvc = require'pvc'
local ds = require'ds'

--- test some basic internal functions
T.internal = function()
  T.eq(0, pvc.calcDirDepth(1))
  T.eq(0, pvc.calcDirDepth(10))
  T.eq(2, pvc.calcDirDepth(101))
end

T.Patch = function()
  local p = pvc.Patch{id=1, minId=1, maxId=50, depth=0}
  T.eq('1.p',  p:path())
  T.throws('123 has longer length than depth=0', function()
    return p:path(123)
  end)
  p.depth = 2; T.eq('00/12.p', p:path(12))
  p.depth = 4
  T.eq('00/00/12.p',    p:path(12))
  T.eq('00/77/7712.p',  p:path(7712))

  p.id, p.minId, p.maxId, p.depth = 1, 1, 3, 2
  T.eq({1, '00/1.p'}, {p()}) T.eq({2, '00/2.p'}, {p()})
  T.eq({3, '00/3.p'}, {p()}) T.eq(nil          , p())
end


