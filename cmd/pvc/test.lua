
local T = require'civtest'.Test

local pvc = require'pvc'

T.patchPath = function()
  local p = pvc.Patch{depth=1}
  T.eq('1.p',  p:patchPath(1))
  T.throws('12 has longer length than depth=1', function()
    p:patchPath(12)
  end)
  p.depth = 2; T.eq('12.p',     p:patchPath(12))
  p.depth = 4
  T.eq('00/12.p',  p:patchPath(12))
  T.eq('77/7712.p',  p:patchPath(7712))

  error'ok'
end
