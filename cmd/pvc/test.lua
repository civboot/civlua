
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

T.commit = function()
  ix.rmRecursive(D); ix.mkDir(D)
  -- initialize PVC
  local p = pvc.init(D)
  T.eq(D, p.dir); T.eq(D..'.pvc/', p.dot)

  T.path(D, {
    ['.pvcpaths'] = '.pvcpaths\n',
    ['.pvc'] = {
      head = 'branch=main\nid=0'
    },
  })
  T.path(D..'.pvc/main/patch/', {
    depth = '2',
    ['00'] = {
      depth = '0', ['0.p'] = pvc.INIT_PATCH,
      ['0.snap'] = {
        PVC_DONE = '',
        ['.pvcpaths'] = '.pvcpaths\n',
      }
    }
  })
  local b = p:getBranch'main'
  T.eq(0, b:findSnap(1))

  -- copy a file into it and add it
  ix.cp(TD..'story.txt.1', D..'story.txt')
  p:addPaths{'story.txt'}
  T.eq({'.pvcpaths', 'story.txt'}, p:paths())
  T.eq(pvc.Diff{
    dir1=D..'.pvc/main/patch/00/0.snap/', dir2=D,
    equal={}, deleted={},
    changed={'.pvcpaths'}, created={'story.txt'},
  }, p:diff())

  local b, pat = p:commit()
  T.path(pat:full'path', s[[
  # message

  --- .pvcpaths
  +++ .pvcpaths
  @@ -1,0 +2 @@
  +story.txt

  ]]..pth.read(TD..'patch.story.txt.1'))
  local STORY1 = pth.read(TD..'story.txt.1')
  T.path(D, {
    ['.pvcpaths'] = '.pvcpaths\nstory.txt\n',
    ['story.txt'] = STORY1,
  })
  T.eq({b, b:patch(1)}, {p:head()})
  T.eq(pvc.Diff{
    dir1=D..'.pvc/main/patch/00/1.snap/', dir2=D,
    equal={'.pvcpaths', 'story.txt'},
    deleted={}, changed={}, created={},
  }, p:diff())

  -- go backwards
  p:checkout('main', 0)
  assert(not ix.exists(D..'story.txt'))
  T.path(D..'.pvcpaths', '.pvcpaths\n')
  T.eq(pvc.Diff{
    dir1=D..'.pvc/main/patch/00/1.snap/', dir2=D,
    equal={},
    deleted={'story.txt'},
    changed={'.pvcpaths'},
    created={},
  }, p:diff('main',1))

  T.throws('ERROR: current head is not at tip.', function()
    p:commit()
  end)

  -- go forwards
  p:checkout('main', 1)
  local EXPECT1 = {
    ['.pvcpaths'] = '.pvcpaths\nstory.txt\n',
    ['story.txt'] = STORY1,
  }
  T.path(D, EXPECT1)

  -- change story, but don't commit yet
  ix.cp(TD..'story.txt.2', D..'story.txt')
  local STORY2 = pth.read(TD..'story.txt.2')
  local EXPECT2 = ds.copy(EXPECT1)
  EXPECT2['story.txt'] = STORY2
  T.path(D, EXPECT2)

  -- branch
  p:branch'dev'
  T.path(D, EXPECT2)
  T.path(D..'.pvc/dev/patch/00/1.snap/', EXPECT1)
  local b, pat = p:head()
  T.eq({'dev', 1}, {b.name, pat.id})
  T.eq({'story.txt'}, p:diff().changed)

  p:commit()
  p:checkout('dev', 1)
  T.path(D, EXPECT1)
  p:checkout('dev', 2)
  T.path(D, EXPECT2)
end
