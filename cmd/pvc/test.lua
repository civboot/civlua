
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
      at = 'main#0', main = { tip = '0' },
    },
  })
  local Bm = D..'.pvc/main/'
  T.path(Bm..'patch/', {
    depth = '2',
    ['00'] = {
      ['0.snap'] = {
        PVC_DONE = '', ['.pvcpaths'] = '.pvcpaths\n',
      }
    }
  })

  -- copy some files and add them
  ix.cp(TD..'story.txt.1', D..'story.txt')
  ix.cp(TD..'hello.lua.1', D..'hello.lua')

  pth.append(D..'.pvcpaths', 'story.txt')
  pth.append(D..'.pvcpaths', 'hello.lua')
  T.path(D..'.pvcpaths', '.pvcpaths\nstory.txt\nhello.lua\n')
  T.eq(pvc.Diff{
    dir1=D..'.pvc/main/patch/00/0.snap/', dir2=D,
    equal={}, deleted={},
    changed={'.pvcpaths'}, created={'hello.lua', 'story.txt'},
  }, pvc.diff(D))

  local DIFF1 = s[[
  --- .pvcpaths
  +++ .pvcpaths
  @@ -1,0 +2,2 @@
  +hello.lua
  +story.txt

  ]]
  ..pth.read(TD..'patch.hello.lua.1')
  ..'\n'
  ..pth.read(TD..'patch.story.txt.1');

  local br, id = pvc.commit(D)
  T.path(pvc.patchPath(Bm, id, '.p'), DIFF1)

  local STORY1 = pth.read(TD..'story.txt.1')
  local HELLO1 = pth.read(TD..'hello.lua.1')

  T.path(D, {
    ['.pvcpaths'] = '.pvcpaths\nhello.lua\nstory.txt\n',
    ['story.txt'] = STORY1, ['hello.lua'] = HELLO1,
    ['.pvc'] = { at = 'main#1' }
  })
  T.path(Bm, { tip = '1' })
  T.eq({'main', 1}, {pvc.at(D)})
  T.eq(pvc.Diff{
    dir1=D..'.pvc/main/patch/00/1.snap/', dir2=D,
    equal={'.pvcpaths', 'hello.lua', 'story.txt'},
    deleted={}, changed={}, created={},
  }, pvc.diff(D))

  -- go backwards
  pvc.at(D, 'main', 0)
  assert(not ix.exists(D..'story.txt'))
  assert(not ix.exists(D..'hello.lua'))
  T.path(D..'.pvcpaths', '.pvcpaths\n')
  T.eq(pvc.Diff{
    dir1=D..'.pvc/main/patch/00/1.snap/', dir2=D,
    equal={},
    deleted={'hello.lua', 'story.txt'},
    changed={'.pvcpaths'},
    created={},
  }, pvc.diff(D, 'main#1'))

  T.throws('ERROR: working id is not at tip.', function()
    pvc.commit(D)
  end)

  -- go forwards
  pvc.at(D, 'main', 1)
  local EXPECT1 = {
    ['.pvcpaths'] = '.pvcpaths\nhello.lua\nstory.txt\n',
    ['story.txt'] = STORY1, ['hello.lua'] = HELLO1,
  }
  T.path(D, EXPECT1)

  -- change story and delete hello.lua and commit
  local EXPECT2 = ds.copy(EXPECT1)
  local STORY2 = pth.read(TD..'story.txt.2')
  pth.write(D..'story.txt', STORY2); EXPECT2['story.txt'] = STORY2
  ix.rm(D..'hello.lua');             EXPECT2['hello.lua'] = nil
  pvc.pathsUpdate(D, nil, --[[rm=]]{'hello.lua'})
  EXPECT2[pvc.PVCPATHS] = '.pvcpaths\nstory.txt\n'
  T.path(D, EXPECT2)

  pvc.commit(D)
  T.path(Bm, { tip = '2' }); T.eq({'main', 2}, {pvc.at(D)})
  T.path(D, EXPECT2); T.path(Bm..'patch/00/2.snap/', EXPECT2)

  -- Create divergent branch which both modify story.txt
  local STORY3d = pth.read(TD..'story.txt.3d')
  local EXPECT3d = ds.copy(EXPECT2)
    EXPECT3d['story.txt'] = STORY3d

  pvc.branch(D, 'dev', 'main'); pvc.at(D, 'dev')
  local Bd = D..'.pvc/dev/'
  T.path(D, EXPECT2);
  T.eq(Bm..'patch/00/2.snap/', pvc.snapshot(D, 'dev', 2))
  pth.write(D..'story.txt', STORY3d); T.path(D, EXPECT3d)
  pvc.commit(D)
  T.path(Bd, { tip = '3' }); T.eq({'dev', 3}, {pvc.at(D)})
  T.eq({'main', 2}, {pvc.getbase(Bd, 'dev')})

  pvc.at(D, 'main',2)
  T.path(Bm, { tip = '2' }); T.eq({'main', 2}, {pvc.at(D)})
  T.path(D, EXPECT2)

  -- diverge main from dev
  local STORY3m  = pth.read(TD..'story.txt.3')
  local EXPECT3m = ds.copy(EXPECT2, {['story.txt'] = STORY3m})

  pth.write(D..'story.txt', STORY3m); T.path(D, EXPECT3m)
  pvc.commit(D)

  -- just test checkout a few times
  pvc.at(D, 'dev',3);  T.path(D, EXPECT3d)
  pvc.at(D, 'dev',2);  T.path(D, EXPECT2)
  pvc.at(D, 'main',3); T.path(D, EXPECT3m)

  -- perform rebase
  pvc.at(D, 'dev',3);  T.path(D, EXPECT3d)
  pvc.rebase(D, 'dev',3)

  local EXPECT4 = ds.copy(EXPECT2, {['story.txt'] = pth.read(TD..'story.txt.4')})
  T.path(Bd..'patch/00/4.snap/', EXPECT4)
  T.path(D, EXPECT4)
end
