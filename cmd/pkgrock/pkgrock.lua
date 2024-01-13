local DOC = [[
pkgrock: utility for publishing PKG.lua directories
]]

local pkg = require'pkg'
local mty = pkg'metaty'
local ds  = pkg'ds'
local shim = pkg'shim'
local civix = pkg'civix'
local push, sfmt = table.insert, string.format

local UPLOAD = [[luarocks upload %s --api-key=%s]]

local M = {DOC=DOC}
M.ARGS = mty.docTy(mty.record'pkgrock', [[
pkgrock dir1 dir2 ...args
]])
  :fieldMaybe('create', 'boolean'):fdoc[[creates the rocks from PKG.lua files]]
  :fieldMaybe('gitops',  'string'):fdoc[[one or more: add,commit,tag,clean

  clean happens at the end and involves deleting the rocks and commiting
  (but not pushing)
  ]]
  :fieldMaybe('gitpush', 'string'):fdoc[[where to push, i.e: 'origin main']]
  :fieldMaybe('upload',  'string'):fdoc[[
    must be set to the luarocks api key to upload with
  ]]

-- make a rock and return rock, rockpath, PKG
M.makerock = function(dir)
  local path = dir
  if not dir:find'/PKG.lua$' then path = pkg.path.concat{dir, 'PKG.lua'} end
  local ok, p = pkg.load(path); assert(ok, p)
  local rock = p.rockspec or {}
  rock.rockspec_format = rock.rockspec_format or "3.0"
  rock.package = rock.package or p.name
  rock.version = rock.version or p.version
  rock.source = rock.source or {}; local s = rock.source
  local tag = (rock.package..'-'..rock.version)
  s.url = s.url or p.url
  s.dir = s.dir or dir
  s.tag = s.tag or tag
  rock.description = rock.description or {}; local d = rock.description
  d.summary  = d.summary  or p.summary
  d.homepage = d.homepage or p.homepage
  d.license  = d.license  or p.license
  rock.dependencies = rock.dependencies or d.deps
  rock.build = rock.build or {
    type = 'builtin',
    modules = ds.kvtable{pkg.isrcs(p.srcs)},
  }
  local rpath = pkg.path.concat{dir, tag..'.rockspec'}
  local f = io.open(rpath, 'w'); for _, key in ipairs(ds.orderedKeys(rock)) do
    local val = rock[key]
    f:write(key, ' = ')
    mty.fmt(val, mty.FmtSet{pretty=true, itemSep = ',\n', tblSep=''}, f)
    f:write'\n'
  end
  f:close()
  return rock, rpath, p
end

local function execute(...)
  local cmd = string.format(...)
  if not os.execute(cmd) then error('execute failed: '..cmd) end
end

M.exe = function(t)
  if t.gitops then
    assert(os.execute'git diff --quiet --exit-code', 'git repo has diffs')
  end
  local tags, rpaths = {}, {}
  if t.create then for _, dir in ipairs(t) do
    local rock, rpath = M.makerock(dir)
    push(rpaths, rpath); push(tags, assert(rock.source.tag))
  end end
  mty.pnt('?? tags:', tags)
  local gittag = false
  if t.gitops then
    if t.gitops:find'add' then for _, rp in ipairs(rpaths) do
      execute([[git add %s]], rp)
    end end
    if t.gitops:find'commit' then
      execute([[git commit -am 'pkgrock: %s']], table.concat(tags, ' '))
    end
    if t.gitops:find'tag' then
      gittag = true
      for _, tag in ipairs(tags) do execute([[git tag '%s']], tag) end
      end
  end
  if t.gitpush then
    execute([[git push %s%s]], t.gitpush, gittag and ' --tags' or '')
  end
  if t.upload then for _, rp in ipairs(rpaths) do
    execute(UPLOAD, rp, t.upload)
  end end
  if t.gitops and t.gitops:find'clean' then
    execute('rm %s', table.concat(rpaths, ' '))
    execute[[git commit -am 'pkgrock: clean']]
  end
end

M.shim = shim{help = M.DOC, exe = M.exe}
return M
