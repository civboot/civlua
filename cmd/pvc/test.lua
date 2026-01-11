
local T = require'civtest'

local M = require'pvc'
local ds = require'ds'
local info = require'ds.log'.info
local pth = require'ds.path'
local fd = require'fd'
local ix = require'civix'

local pvc = M.pvc
local TD, D = 'cmd/pvc/testdata/', '.out/pvc/'
local pc = pth.concat
local s = ds.simplestr

fd.ioStd()

--- test some basic internal functions
T.internal = function()
  T.eq(0, M._calcPatchDepth(1))
  T.eq(0, M._calcPatchDepth(10))
  T.eq(2, M._calcPatchDepth(101))
end

T.patchPath = function()
  T.eq('foo/commit/00/1.p', M._patchPath('foo', 1, '.p', 2))
end

local initPvc = function(d) --> projDir
  d = d or D
  ix.rmRecursive(d);
  pvc.init{dir=d}
  return d
end

--- test empty files
T.empty = function()
  local d = initPvc()
  local diff = pvc.diff{dir=d, paths=true}
  T.eq(M.Diff{
    dir1=D..'.pvc/main/commit/00/0.snap/', dir2=D,
    equal={".pvcpaths"}, deleted={},
    changed={}, created={},
  }, diff)
  T.eq(false, diff:hasDiff())
  T.throws('no differences detected', function()
    pvc.commit{dir=d, '--', 'empty repo'}
  end)
  pth.write(d..'empty.txt', '')
  pth.append(d..'.pvcpaths', 'empty.txt')
  T.throws('has a size of 0', function()
    pvc.commit{dir=d, '--', 'commit empty.txt'}
  end)
end

-- binary not supported
T.binary = function()
  local P = initPvc()
  local bpath, BIN = P..'bin', '\x00\xFF'
  pth.write(bpath, BIN)
  pth.append(P..'.pvcpaths', 'bin')
  T.throws('Binary files /dev/null and bin differ', function()
    pvc.commit{dir=P, '--', 'commit binary file'}
  end)
end

-- missing path is an error
T.missingPath = function()
  local P = initPvc()
  pth.append(P..'.pvcpaths', 'file.dne')
  T.throws('but does not exist', function()
    pvc.commit{dir=P, '--', 'commit path dne'}
  end)
end

local HELLO_PATCH1 = [[
--- /dev/null
+++ hello/hello.lua
@@ -0,0 +1,5 @@
+local M = {}
+
+M.helloworld = function()
+  print'hello world'
+end
]]

local STORY_PATCH1 = [[
--- /dev/null
+++ story.txt
@@ -0,0 +1,4 @@
+# Story
+This is a story
+about a man
+and his dog.
]]

--- This test is large but does an entire "common" workflow
T'workflow' do
  info('@@ started workflow D=%q', D)
  ix.rmRecursive(D);
  -- initialize PVC
  pvc.init{dir=D}
  T.eq({'main'}, M.branches(D))
  T.path(D, {
    ['.pvcpaths'] = '.pvcpaths\n',
    ['.pvc'] = {
      at = 'main#0', main = { tip = '0' },
    },
  })
  local Bm = D..'.pvc/main/'
  T.path(Bm..'commit/', {
    depth = '2',
    ['00'] = {
      ['0.snap'] = {
        PVC_DONE = '', ['.pvcpaths'] = '.pvcpaths\n',
      }
    }
  })

  -- copy some files and add them
  ix.cp(TD..'story.txt.1',      D..'story.txt')
  ix.forceCp(TD..'hello.lua.1', D..'hello/hello.lua')

  pth.append(D..'.pvcpaths', 'story.txt')
  pth.append(D..'.pvcpaths', 'hello/hello.lua')
  T.path(D..'.pvcpaths', '.pvcpaths\nstory.txt\nhello/hello.lua\n')
  T.eq(M.Diff{
    dir1=D..'.pvc/main/commit/00/0.snap/', dir2=D,
    equal={}, deleted={},
    changed={'.pvcpaths'}, created={'hello/hello.lua', 'story.txt'},
  }, pvc.diff{dir=D, paths=true})

  local DIFF1 = s[[
  desc1
  --- .pvcpaths
  +++ .pvcpaths
  @@ -1,0 +2,2 @@
  +hello/hello.lua
  +story.txt

  ]]
  ..HELLO_PATCH1
  ..'\n'
  ..STORY_PATCH1;

  local br, id = pvc.commit{dir=D, '--', 'desc1'}
  local p1 = M._patchPath(Bm, id, '.p')
  T.path(p1, DIFF1)
  T.eq({'desc1'}, M._desc(p1))
  pvc.desc{dir=D, '--', 'desc1', '-', 'edited'}
  T.eq({'desc1 - edited'}, M._desc(p1))

  local STORY1 = pth.read(TD..'story.txt.1')
  local HELLO1 = pth.read(TD..'hello.lua.1')

  T.path(D, {
    ['.pvcpaths'] = '.pvcpaths\nhello/hello.lua\nstory.txt\n',
    ['story.txt'] = STORY1, hello = {['hello.lua'] = HELLO1},
    ['.pvc'] = { at = 'main#1' }
  })
  T.path(Bm, { tip = '1' })
  T.eq({'main#1'}, {pvc.at{dir=D}})
  T.eq(M.Diff{
    dir1=D..'.pvc/main/commit/00/1.snap/', dir2=D,
    equal={'.pvcpaths', 'hello/hello.lua', 'story.txt'},
    deleted={}, changed={}, created={},
  }, pvc.diff{dir=D, paths=true})

  -- go backwards
  pvc.at{dir=D, 'main#0'}
  assert(not ix.exists(D..'story.txt'))
  assert(not ix.exists(D..'hello/hello.lua'))
  T.path(D..'.pvcpaths', '.pvcpaths\n')
  T.eq(M.Diff{
    dir1=D..'.pvc/main/commit/00/1.snap/', dir2=D,
    equal={},
    deleted={'hello/hello.lua', 'story.txt'},
    changed={'.pvcpaths'},
    created={},
  }, pvc.diff{dir=D, paths=true, 'main#1'})

  T.throws('ERROR: working id is not at tip.', function()
    pvc.commit{dir=D, '--', 'desc error'}
  end)

  -- go forwards
  M.atId(D, 'main', 1)
  local EXPECT1 = {
    ['.pvcpaths'] = '.pvcpaths\nhello/hello.lua\nstory.txt\n',
    ['story.txt'] = STORY1, hello = { ['hello.lua'] = HELLO1 },
  }
  T.path(D, EXPECT1)

  -- change story and delete hello.lua and commit
  local EXPECT2 = ds.copy(EXPECT1)
  local STORY2 = pth.read(TD..'story.txt.2')
  pth.write(D..'story.txt', STORY2); EXPECT2['story.txt'] = STORY2
  ix.rmRecursive(D..'hello/');       EXPECT2.hello = nil
  M._pathsUpdate(D, nil, --[[rm=]]{'hello/hello.lua'})
  EXPECT2[M.PVCPATHS] = '.pvcpaths\nstory.txt\n'
  T.path(D, EXPECT2)

  pvc.commit{dir=D, '--', 'desc2'}
  T.path(Bm, { tip = '2' }); T.eq({'main', 2}, {M.atId(D)})
  T.path(D, EXPECT2); T.path(Bm..'commit/00/2.snap/', EXPECT2)

  -- Create divergent branch which both modify story.txt
  local STORY3d = pth.read(TD..'story.txt.3d')
  local EXPECT3d = ds.copy(EXPECT2)
    EXPECT3d['story.txt'] = STORY3d

  pvc.branch{dir=D, 'dev', 'main'}
  M.atId(D, 'dev')
  T.eq({'dev', 'main'}, M.branches(D))
  local Bd = D..'.pvc/dev/'
  T.path(D, EXPECT2);
  T.eq(Bm..'commit/00/2.snap/', M.snapshot(D, 'dev', 2))
  pth.write(D..'story.txt', STORY3d); T.path(D, EXPECT3d)
  pvc.commit{dir=D, '--', 'desc3d'}
  T.path(Bd, { tip = '3' }); T.eq({'dev', 3}, {M.atId(D)})
  T.eq({'main', 2}, {M._getbase(Bd, 'dev')})

  local STORY4d = pth.read(TD..'story.txt.4d')
  pth.write(D..'story.txt', STORY4d)
  local EXPECT4d = ds.copy(EXPECT3d, {
    ['story.txt'] = STORY4d
  })
  pvc.commit{dir=D, '--', 'desc4d'}

  M.atId(D, 'main',2)
  T.path(Bm, { tip = '2' }); T.eq({'main', 2}, {M.atId(D)})
  T.path(D, EXPECT2)

  -- diverge main from dev
  local STORY3m  = pth.read(TD..'story.txt.3')
  local EXPECT3m = ds.copy(EXPECT2, {['story.txt'] = STORY3m})

  pth.write(D..'story.txt', STORY3m); T.path(D, EXPECT3m)
  pvc.commit{dir=D, '--', 'desc3'}

  -- just test checkout a few times
  M.atId(D, 'dev',3);  T.path(D, EXPECT3d)
  M.atId(D, 'dev',2);  T.path(D, EXPECT2)
  M.atId(D, 'main',3); T.path(D, EXPECT3m)
  M.atId(D, 'dev',4);  T.path(D, EXPECT4d)

  -- perform rebase
  pvc.rebase{dir=D, 'dev', 3}
  ds.yeet'ok'
  T.eq({'dev', 5}, {M._rawat(D)})
  T.eq(3, pvc.tip{dir=Bm})
  T.eq(5, pvc.tip{dir=Bd})
  T.eq({'desc4d'}, M._desc(Bd..'commit/00/5.p'))

  local EXPECT5 = ds.copy(EXPECT2, {
    ['story.txt'] = pth.read(TD..'story.txt.5')
  })
  T.path(Bd..'commit/00/5.snap/', EXPECT5)
  M.atId(D, 'main',3); T.path(D, EXPECT3m)
  M.atId(D, 'dev',4);

  -- dev4 has main3's changes.
  local EXPECT4 = ds.copy(EXPECT3d, {
    ['story.txt'] = STORY3d:gsub('unhappy', 'happy'),
  })
  T.path(D, EXPECT4)

  M._grow(D, 'main', 'dev')
  T.eq(5, M._rawtip(Bm))
  T.eq({'main', 5}, {M.atId(D)})
  assert(not ix.exists(Bd))
  T.path(M.snapshot(D, 'main', 5), EXPECT5)
  T.path(M.snapshot(D, 'main', 4), EXPECT4)

  -- Squash main commit and first dev commit
  M._squash(D, 'main', 3,4)
  T.eq(4, M._rawtip(Bm))
  T.path(M.snapshot(D, 'main', 2), EXPECT2)
  T.path(M.snapshot(D, 'main', 3), EXPECT4)
  M.atId(D, 'main',2); T.path(D, EXPECT2)
  M.atId(D, 'main',3); T.path(D, EXPECT4)
  M.atId(D, 'main',4); T.path(D, EXPECT5)
end
