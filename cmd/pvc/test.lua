
local T = require'civtest'.Test

local pvc = require'pvc'
local ds = require'ds'
local pth = require'ds.path'
local ix = require'civix'

local TD, D = 'cmd/pvc/testdata/', '.out/pvc/'
local pc = pth.concat
local s = ds.simplestr

--- test some basic internal functions
T.internal = function()
  T.eq(0, pvc.calcPatchDepth(1))
  T.eq(0, pvc.calcPatchDepth(10))
  T.eq(2, pvc.calcPatchDepth(101))
end

T.patchPath = function()
  T.eq('foo/patch/00/1.p', pvc.patchPath('foo', 1, '.p', 2))
end

--- This test is large but does an entire "common" workflow
T.workflow = function()
  ix.rmRecursive(D);
  -- initialize PVC
  pvc.init(D)
  T.path(D, {
    ['.pvcpaths'] = '.pvcpaths\n',
    ['.pvc'] = {
      head = 'main#0', main = { tip = '0' },
    },
  })
  local B = D..'.pvc/main/'
  T.path(B..'patch/', {
    depth = '2',
    ['00'] = {
      ['0.snap'] = {
        PVC_DONE = '', ['.pvcpaths'] = '.pvcpaths\n',
      }
    }
  })

  T.eq({B..'patch/00/0.snap/', 0}, {pvc.findSnap(B, 0, 0)})

  -- copy a file into it and add it
  ix.cp(TD..'story.txt.1', D..'story.txt')

  pth.append(D..'.pvcpaths', 'story.txt')
  T.path(D..'.pvcpaths',     '.pvcpaths\nstory.txt\n')
  T.eq(pvc.Diff{
    dir1=D..'.pvc/main/patch/00/0.snap/', dir2=D,
    equal={}, deleted={},
    changed={'.pvcpaths'}, created={'story.txt'},
  }, pvc.diff(D))


  local DIFF1 = s[[
  --- .pvcpaths
  +++ .pvcpaths
  @@ -1,0 +2 @@
  +story.txt

  ]]..pth.read(TD..'patch.story.txt.1')
  T.eq(DIFF1, pvc.diff(D):patch())

  local br, id = pvc.commit(D)
  T.path(pvc.patchPath(B, id, '.p'), DIFF1)

  local STORY1 = pth.read(TD..'story.txt.1')
  T.path(D, {
    ['.pvcpaths'] = '.pvcpaths\nstory.txt\n',
    ['story.txt'] = STORY1,
  })
  T.eq({'main', 1}, {pvc.head(D)})
  T.eq(pvc.Diff{
    dir1=D..'.pvc/main/patch/00/1.snap/', dir2=D,
    equal={'.pvcpaths', 'story.txt'},
    deleted={}, changed={}, created={},
  }, pvc.diff(D))

  -- -- go backwards
  -- p:checkout('main', 0)
  -- assert(not ix.exists(D..'story.txt'))
  -- T.path(D..'.pvcpaths', '.pvcpaths\n')
  -- T.eq(pvc.Diff{
  --   dir1=D..'.pvc/main/patch/00/1.snap/', dir2=D,
  --   equal={},
  --   deleted={'story.txt'},
  --   changed={'.pvcpaths'},
  --   created={},
  -- }, p:diff('main',1))

  -- T.throws('ERROR: current head is not at tip.', function()
  --   p:commit()
  -- end)

  -- -- go forwards
  -- p:checkout('main', 1)
  -- local EXPECT1 = {
  --   ['.pvcpaths'] = '.pvcpaths\nstory.txt\n',
  --   ['story.txt'] = STORY1,
  -- }
  -- T.path(D, EXPECT1)

  -- -- change story, but don't commit yet
  -- ix.cp(TD..'story.txt.2', D..'story.txt')
  -- local STORY2 = pth.read(TD..'story.txt.2')
  -- local EXPECT2 = ds.copy(EXPECT1)
  -- EXPECT2['story.txt'] = STORY2
  -- T.path(D, EXPECT2)

  -- -- branch
  -- p:branch'dev'
  -- T.path(D, EXPECT2)
  -- T.path(D..'.pvc/dev/patch/00/1.snap/', EXPECT1)
  -- local b, pat = p:head()
  -- T.eq({'dev', 1}, {b.name, pat.id})
  -- T.eq({'story.txt'}, p:diff().changed)

  -- p:commit()
  -- p:checkout('dev', 1)
  -- T.path(D, EXPECT1)
  -- p:checkout('dev', 2)
  -- T.path(D, EXPECT2)
end
