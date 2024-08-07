local DOC = [[
pkgrock: utility for publishing PKG.lua directories

Example (sh):
  , rock lib/pkg --create --gitops='add commit tag' \
    --gitpush='origin main --tags' --upload=$ROCKAPI
]]

local pkg = require'pkglib'
local mty = require'metaty'
local ds  = require'ds'
local shim = require'shim'
local civix = require'civix'
local push, sfmt = table.insert, string.format
local pth = require'ds.path'

local UPLOAD = [[luarocks upload %s --api-key=%s]]

local M = {DOC=DOC}

-- pkgrock dir1 dir2 ...args
M.ARGS = mty'pkgrock' {
  [[create [bool]   creates the rocks from PKG.lua files]],
  [[gitops [string] one or more: add,commit,tag]],
  [[gitpush[string] where to push, i.e: 'origin main']],
  [[upload [string] set to the luarocks api key]],
}

M.rockpath = function(dir, tag)
  return pth.concat{dir, tag..'.rockspec'}
end

-- make a rock and return rock, rockpath, PKG
M.makerock = function(dir)
  local path = dir
  if not dir:find'/PKG.lua$' then path = pth.concat{dir, 'PKG.lua'} end
  print('... loading pkg', path)
  local p = pkg.load('noname', path)
  local rock = p.rockspec or {}
  rock.rockspec_format = rock.rockspec_format or "3.0"
  rock.package = rock.package or p.name
  rock.version = rock.version or p.version
  rock.source = rock.source or {}; local s = rock.source
  local tag = (rock.package..'-'..rock.version)
  s.url = s.url or p.url
  s.dir = s.dir or pth.concat{select(2, pth.last(p.url)), dir} -- luarocks#1675
  s.tag = s.tag or tag
  rock.description = rock.description or {}; local d = rock.description
  d.summary  = d.summary  or p.summary
  d.homepage = d.homepage or p.homepage
  d.license  = d.license  or p.license
  rock.dependencies = rock.dependencies or p.deps
  rock.build = rock.build or {
    type = 'builtin', modules = pkg.modules(p.srcs),
  }
  local rpath = M.rockpath(dir, tag)
  print('... writing rockspec', rpath)
  local fmt = mty.Fmt:pretty{
    to=io.open(rpath, 'w'),
    indexEnd = ',\n', keyEnd=',\n'
  }
  for _, key in ipairs(ds.orderedKeys(rock)) do
    local val = rock[key]
    fmt:write(key, ' = ')
    fmt(val); fmt:write'\n'
  end
  fmt.to:close()
end

M.loadrock = function(dir)
  local p = pkg.load(dir, pth.concat{dir, 'PKG.lua'})
  local rpath = M.rockpath(dir, p.name..'-'..p.version)
  return rpath, pkg.load(p.name, rpath)
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
    print('making rock', dir)
    M.makerock(dir)
  end end
  for _, dir in ipairs(t) do
    local rpath, rock = M.loadrock(dir)
    push(rpaths, rpath); push(tags, assert(rock.source.tag))
  end
  if gitops.tag then
    print'... getting tags'
    local out = civix.sh'git tag'
    local exist = ds.Set(require'lines'(out))
      :union(ds.Set(tags))
    if not ds.isEmpty(exist) then error(
      'tags already exist: '..table.concat(ds.orderedKeys(exist), ' ')
    )end
  end
  if gitops.add then for _, rp in ipairs(rpaths) do
    print('git add:', rp)
    execute([[git add -f %s]], rp)
  end end
  if gitops.commit then
    print'... commiting'
    execute([[git commit -am 'pkgrock: %s']], table.concat(tags, ' '))
  end
  if gitops.tag then for _, tag in ipairs(tags) do
    print('add tag:', tag)
    execute([[git tag '%s']], tag)
  end end
  if t.gitpush then
    print'... pushing'
    execute([[git push %s]], t.gitpush)
  end
  if t.upload then for _, rp in ipairs(rpaths) do
    print('uploading', rp)
    execute(UPLOAD, rp, t.upload)
  end end
end

M.shim = shim{help = M.DOC, exe = M.exe}
return M
