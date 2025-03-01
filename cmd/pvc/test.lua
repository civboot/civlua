
local T = require'civtest'.Test

local pvc = require'pvc'
local ds = require'ds'
local pth = require'ds.path'
local ix = require'civix'

local TD, D = 'cmd/pvc/testdata/', '.out/pvc/'
local pc = pth.concat

--- test some basic internal functions
T.internal = function()
  T.eq(0, pvc.calcDepth(1))
  T.eq(0, pvc.calcDepth(10))
  T.eq(2, pvc.calcDepth(101))
end

T.Patch = function()
  local p = pvc.Patch{id=1, depth=0}
  T.eq('1.p',  p:path())
  T.eq(nil, p:path(123))
  p.depth = 2; T.eq('00/12.p', p:path(12))
  p.depth = 4
  T.eq('00/00/12.p',    p:path(12))
  T.eq('00/77/7712.p',  p:path(7712))
  T.eq(nil,             p:path(1234567))

  p.id, p.depth = 9997, 2
  T.eq({9997, '99/9997.p'}, {p()})
  T.eq({9998, '99/9998.p'}, {p()})
  T.eq({9999, '99/9999.p'}, {p()})
  T.eq({}                 , {p()})
end

T.patch = function()
  ix.rmRecursive(D); ix.mkDir(D)
  -- initialize PVC
  local p = pvc.init(D)
  local dot = '.out/pvc/.pvc/'; T.eq(dot, p.dot)
  T.exists(dot..'main/files')
  local main = p:branch'main'

  -- copy a file into it and add it
  ix.cp(TD..'story.txt.1', D..'story.txt')
  main:files{'story.txt'}
  T.eq({'story.txt'}, main:files())

  -- commit the changes
  -- main:commit()
end
