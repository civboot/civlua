local DOC = [[
pkgrock: utility for publishing PKG.lua directories

Example (sh):
  , rock lib/pkg --create --gitops='add commit tag' \
    --gitpush='origin main --tags' --upload=$ROCKAPI
]]

local pkg = require'pkg'
local mty = pkg'metaty'
local ds  = pkg'ds'
local shim = pkg'shim'
local civix = pkg'civix'
local push, sfmt = table.insert, string.format

local UPLOAD = [[luarocks upload %s --api-key=%s]]

local M = {DOC=DOC}
M.ARGS = mty.doc[[
pkgrock dir1 dir2 ...args
]](mty.record2'pkgrock') {
  [[create [bool]   creates the rocks from PKG.lua files]],
  [[gitops [string] one or more: add,commit,tag]],
  [[gitpush[string] where to push, i.e: 'origin main']],
  [[upload [string] set to the luarocks api key]],
}

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
  rock.dependencies = rock.dependencies or p.deps
  rock.build = rock.build or {
    type = 'builtin',
    modules = ds.kvtable{pkg.isrcs(p.srcs)},
  }
  local rpath = pkg.path.concat{dir, tag..'.rockspec'}
  local f = io.open(rpath, 'w'); for _, key in ipairs(ds.orderedKeys(rock)) do
    local val = rock[key]
    f:write(key, ' = ')
    local fset = mty.FmtSet{pretty=true, itemSep = ',\n', listSep=',\n', tblSep=''}
    mty.fmt(val, fset, f)
    f:write'\n'
  end
  f:close()
  return rock, rpath, p
end

local function execute(...)
  local cmd = string.format(...)
  print('executing:', cmd)
  if not os.execute(cmd) then error('execute failed: '..cmd) end
end

M.exe = function(t)
  if t.gitops then
    assert(os.execute'git diff --quiet --exit-code', 'git repo has diffs')
  end
  local gitops = ds.Set(shim.listSplit(t.gitops))
  local tags, rpaths = {}, {}
  if t.create then for _, dir in ipairs(t) do
    local rock, rpath = M.makerock(dir)
    push(rpaths, rpath); push(tags, assert(rock.source.tag))
  end end
  if gitops.tag then
    local rc, out, log = civix.sh'git tag'
    local exist = ds.Set(ds.lines(out))
      :union(ds.Set(tags))
    if not ds.isEmpty(exist) then error(
      'tags already exist: '..table.concat(ds.orderedKeys(exist), ' ')
    )end
  end
  if gitops.add then for _, rp in ipairs(rpaths) do
    execute([[git add -f %s]], rp)
  end end
  if gitops.commit then
    execute([[git commit -am 'pkgrock: %s']], table.concat(tags, ' '))
  end
  if gitops.tag then for _, tag in ipairs(tags) do
    execute([[git tag '%s']], tag)
  end end
  if t.gitpush then
    execute([[git push %s]], t.gitpush)
  end
  if t.upload then for _, rp in ipairs(rpaths) do
    execute(UPLOAD, rp, t.upload)
  end end
end

M.shim = shim{help = M.DOC, exe = M.exe}
return M
