local M = mod'pkgrock'
MAIN = MAIN or M
local mty = require'metaty'
local fmt = require'fmt'

--- utility for publishing PKG.lua directories. Usage: [##
---   pkgrock dir1 dir2 ...args]
--- ]##
---
--- Example (sh): [##
---   , rock lib/pkg --create --gitops='add commit tag' \
---     --gitpush='origin main --tags' --upload=$ROCKAPI
--- ]##
M.Args = mty'pkgrock' {
  [[create [bool]   creates the rocks from PKG.lua files]],
  [[gitops [string] one or more: add,commit,tag]],
  [[gitpush[string] where to push, i.e: 'origin main']],
  [[upload [string] set to the luarocks api key]],
}

local pkg = require'pkglib'
local ds  = require'ds'
local shim = require'shim'
local civix = require'civix'
local push, sfmt = table.insert, string.format
local pth = require'ds.path'

local UPLOAD = [[luarocks upload %s --api-key=%s]]

M.rockpath = function(dir, tag)
  return pth.concat{dir, tag..'.rockspec'}
end

-- make a rock and return rock, rockpath, PKG
M.makerock = function(styled, dir)
  local path = dir
  if not dir:find'/PKG.lua$' then path = pth.concat{dir, 'PKG.lua'} end
  styled('... loading pkg', path)
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
  styled('... writing rockspec', rpath)
  local fmt = fmt.Fmt:pretty{
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

local function execute(styler, ...)
  local cmd = string.format(...)
  styler:styled('code', 'executing: '..cmd, '\n')
  if not os.execute(cmd) then error('execute failed: '..cmd) end
end

M.main = function(t)
  t = M.Args(shim.parseStr(t))
  require'civ'.setupFmt()
  local to = io.fmt
  local styled = function(...)
    to:styled('notify', table.concat({...}, '\t'), '\n')
  end
  if t.gitops then
    assert(os.execute'git diff --quiet --exit-code', 'git repo has diffs')
  end
  local gitops = ds.Set(shim.listSplit(t.gitops))
  local tags, rpaths = {}, {}
  if t.create then for _, dir in ipairs(t) do
    styled('making rock', dir)
    M.makerock(styled, dir)
  end end
  for _, dir in ipairs(t) do
    local rpath, rock = M.loadrock(dir)
    push(rpaths, rpath); push(tags, assert(rock.source.tag))
  end
  if gitops.tag then
    styled'... getting tags'
    local out = civix.sh'git tag'
    local exist = ds.Set(require'lines'(out))
      :union(ds.Set(tags))
    if not ds.isEmpty(exist) then error(
      'tags already exist: '..table.concat(ds.orderedKeys(exist), ' ')
    )end
  end
  if gitops.add then for _, rp in ipairs(rpaths) do
    styled('git add:', rp)
    execute(io.fmt, [[git add -f %s]], rp)
  end end
  if gitops.commit then
    styled'... commiting'
    execute(io.fmt, [[git commit -am 'pkgrock: %s']], table.concat(tags, ' '))
  end
  if gitops.tag then for _, tag in ipairs(tags) do
    styled('add tag:', tag)
    execute(io.fmt, [[git tag '%s']], tag)
  end end
  if t.gitpush then
    styled'... pushing'
    execute(io.fmt, [[git push %s]], t.gitpush)
  end
  if t.upload then for _, rp in ipairs(rpaths) do
    styled('uploading', rp)
    execute(io.fmt, UPLOAD, rp, t.upload)
  end end
end

if M == MAIN then M.main(shim.parse(arg)); os.exit(0) end
return M
