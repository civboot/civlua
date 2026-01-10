
local T = require'civtest'

local pvc = require'pvc'
local ds = require'ds'
local info = require'ds.log'.info
local pth = require'ds.path'
local fd = require'fd'
local ix = require'civix'

local TD, D = 'cmd/pvc/testdata/', '.out/pvc/'
local pc = pth.concat
local s = ds.simplestr

fd.ioStd()

--- test some basic internal functions
T.internal = function()
  T.eq(0, pvc._calcPatchDepth(1))
  T.eq(0, pvc._calcPatchDepth(10))
  T.eq(2, pvc._calcPatchDepth(101))
end

T.patchPath = function()
  T.eq('foo/commit/00/1.p', pvc._patchPath('foo', 1, '.p', 2))
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
  local diff = pvc._diff(D)
  T.eq(pvc.Diff{
    dir1=D..'.pvc/main/commit/00/0.snap/', dir2=D,
    equal={".pvcpaths"}, deleted={},
    changed={}, created={},
  }, diff)
  T.eq(false, diff:hasDiff())
  T.throws('no differences detected', function()
    pvc._commit(d, 'empty repo')
  end)
  pth.write(d..'empty.txt', '')
  pth.append(d..'.pvcpaths', 'empty.txt')
  T.throws('has a size of 0', function()
    pvc._commit(d, 'commit empty.txt')
  end)
end

-- binary not supported
T.binary = function()
  local P = initPvc()
  local bpath, BIN = P..'bin', '\x00\xFF'
  pth.write(bpath, BIN)
  pth.append(P..'.pvcpaths', 'bin')
  T.throws('Binary files /dev/null and bin differ', function()
    pvc._commit(P, 'commit binary file')
  end)
end

-- missing path is an error
T.missingPath = function()
  local P = initPvc()
  pth.append(P..'.pvcpaths', 'file.dne')
  T.throws('but does not exist', function()
    pvc._commit(P, 'commit path dne')
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
-- T.workflow = function()
local function workflow() -- FIXME: broken on linux
  ix.rmRecursive(D);
  -- initialize PVC
  pvc.init{D}
  T.eq({'main'}, pvc.branches(D))
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
  T.eq(pvc.Diff{
    dir1=D..'.pvc/main/commit/00/0.snap/', dir2=D,
    equal={}, deleted={},
    changed={'.pvcpaths'}, created={'hello/hello.lua', 'story.txt'},
  }, pvc.diff(D))

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

  local br, id = pvc._commit(D, 'desc1')
  local p1 = pvc._patchPath(Bm, id, '.p')
  T.path(p1, DIFF1)
  T.eq({'desc1'}, pvc._desc(p1))
  pvc.main.desc{'--', 'desc1', '-', 'edited', dir=D}
  T.eq({'desc1 - edited'}, pvc._desc(p1))

  local STORY1 = pth.read(TD..'story.txt.1')
  local HELLO1 = pth.read(TD..'hello.lua.1')

  T.path(D, {
    ['.pvcpaths'] = '.pvcpaths\nhello/hello.lua\nstory.txt\n',
    ['story.txt'] = STORY1, hello = {['hello.lua'] = HELLO1},
    ['.pvc'] = { at = 'main#1' }
  })
  T.path(Bm, { tip = '1' })
  T.eq({'main', 1}, {pvc.atId(D)})
  T.eq(pvc.Diff{
    dir1=D..'.pvc/main/commit/00/1.snap/', dir2=D,
    equal={'.pvcpaths', 'hello/hello.lua', 'story.txt'},
    deleted={}, changed={}, created={},
  }, pvc.diff(D))

  -- go backwards
  pvc.atId(D, 'main', 0)
  assert(not ix.exists(D..'story.txt'))
  assert(not ix.exists(D..'hello/hello.lua'))
  T.path(D..'.pvcpaths', '.pvcpaths\n')
  T.eq(pvc.Diff{
    dir1=D..'.pvc/main/commit/00/1.snap/', dir2=D,
    equal={},
    deleted={'hello/hello.lua', 'story.txt'},
    changed={'.pvcpaths'},
    created={},
  }, pvc.diff(D, 'main#1'))

  T.throws('ERROR: working id is not at tip.', function()
    pvc._commit(D, 'desc error')
  end)

  -- go forwards
  pvc.atId(D, 'main', 1)
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
  pvc._pathsUpdate(D, nil, --[[rm=]]{'hello/hello.lua'})
  EXPECT2[pvc.PVCPATHS] = '.pvcpaths\nstory.txt\n'
  T.path(D, EXPECT2)

  pvc._commit(D, 'desc2')
  T.path(Bm, { tip = '2' }); T.eq({'main', 2}, {pvc.atId(D)})
  T.path(D, EXPECT2); T.path(Bm..'commit/00/2.snap/', EXPECT2)

  -- Create divergent branch which both modify story.txt
  local STORY3d = pth.read(TD..'story.txt.3d')
  local EXPECT3d = ds.copy(EXPECT2)
    EXPECT3d['story.txt'] = STORY3d

  pvc._branch(D, 'dev', 'main'); pvc.atId(D, 'dev')
  T.eq({'dev', 'main'}, pvc.branches(D))
  local Bd = D..'.pvc/dev/'
  T.path(D, EXPECT2);
  T.eq(Bm..'commit/00/2.snap/', pvc.snapshot(D, 'dev', 2))
  pth.write(D..'story.txt', STORY3d); T.path(D, EXPECT3d)
  pvc._commit(D, 'desc3d')
  T.path(Bd, { tip = '3' }); T.eq({'dev', 3}, {pvc.atId(D)})
  T.eq({'main', 2}, {pvc._getbase(Bd, 'dev')})

  local STORY4d = pth.read(TD..'story.txt.4d')
  pth.write(D..'story.txt', STORY4d)
  local EXPECT4d = ds.copy(EXPECT3d, {
    ['story.txt'] = STORY4d
  })
  pvc._commit(D, 'desc4d')

  pvc.atId(D, 'main',2)
  T.path(Bm, { tip = '2' }); T.eq({'main', 2}, {pvc.atId(D)})
  T.path(D, EXPECT2)

  -- diverge main from dev
  local STORY3m  = pth.read(TD..'story.txt.3')
  local EXPECT3m = ds.copy(EXPECT2, {['story.txt'] = STORY3m})

  pth.write(D..'story.txt', STORY3m); T.path(D, EXPECT3m)
  pvc._commit(D, 'desc3')

  -- just test checkout a few times
  pvc.atId(D, 'dev',3);  T.path(D, EXPECT3d)
  pvc.atId(D, 'dev',2);  T.path(D, EXPECT2)
  pvc.atId(D, 'main',3); T.path(D, EXPECT3m)
  pvc.atId(D, 'dev',4);  T.path(D, EXPECT4d)

  -- perform rebase
  pvc.rebase(D, 'dev',3)
  T.eq({'dev', 5}, {pvc._rawat(D)})
  T.eq(3, pvc._rawtip(Bm))
  T.eq(5, pvc._rawtip(Bd))
  T.eq({'desc4d'}, pvc._desc(Bd..'commit/00/5.p'))

  local EXPECT5 = ds.copy(EXPECT2, {
    ['story.txt'] = pth.read(TD..'story.txt.5')
  })
  T.path(Bd..'commit/00/5.snap/', EXPECT5)
  pvc.atId(D, 'main',3); T.path(D, EXPECT3m)
  pvc.atId(D, 'dev',4);

  -- dev4 has main3's changes.
  local EXPECT4 = ds.copy(EXPECT3d, {
    ['story.txt'] = STORY3d:gsub('unhappy', 'happy'),
  })
  T.path(D, EXPECT4)

  pvc._grow(D, 'main', 'dev')
  T.eq(5, pvc._rawtip(Bm))
  T.eq({'main', 5}, {pvc.atId(D)})
  assert(not ix.exists(Bd))
  T.path(pvc.snapshot(D, 'main', 5), EXPECT5)
  T.path(pvc.snapshot(D, 'main', 4), EXPECT4)

  -- Squash main commit and first dev commit
  pvc._squash(D, 'main', 3,4)
  T.eq(4, pvc._rawtip(Bm))
  T.path(pvc.snapshot(D, 'main', 2), EXPECT2)
  T.path(pvc.snapshot(D, 'main', 3), EXPECT4)
  pvc.atId(D, 'main',2); T.path(D, EXPECT2)
  pvc.atId(D, 'main',3); T.path(D, EXPECT4)
  pvc.atId(D, 'main',4); T.path(D, EXPECT5)
end
