
local T = require'civtest'.Test

local pvc = require'pvc'
local ds = require'ds'

T.Patch = function()
  local p = pvc.Patch{}:depth(2)
  T.eq('1.p',  p:patchPath(1))
  T.throws('123 has longer length than depth=2', function()
    p:patchPath(123)
  end)
  p:depth(2); T.eq('12.p',     p:patchPath(12))
  p:depth(4)
  T.eq('00/12.p',    p:patchPath(12))
  T.eq('77/7712.p',  p:patchPath(7712))

  p.id, p.minId, p.maxId = 1, 1, 3
  T.eq({1, '00/1.p'}, {p()}) T.eq({2, '00/2.p'}, {p()})
  T.eq({3, '00/3.p'}, {p()}) T.eq(nil          , p())
end


