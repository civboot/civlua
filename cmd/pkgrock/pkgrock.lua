DOC = [[
pkgrock: utility for publishing PKG.lua directories
]]

local pkg = require'pkg'
local mty = pkg'metaty'
local ds  = pkg'ds'
local shim = pkg'shim'
local civix = pkg'civix'

local M = {}

-- description = {
--   summary = "Simple but effective Lua type system using metatables",
--   homepage = "https://github.com/civboot/civlua/blob/main/metaty/README.md",
--   license = "UNLICENSE",
-- }

-- make a rock and return rockpath, PKG, rock
M.makerock = function(dir)
  local path = dir
  if not dir:find'/PKG.lua$' then path = pkg.concat{dir, 'PKG.lua'} end
  local p = pkg.load(path)
  local rock = p.rockspec or {}
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
  local f = open(rpath, 'w'); for _, key in ipairs(ds.orderedKeys(rock)) do
    local val = rock[key]
    f:write(key, ' = ')
    mty.fmt(val, mty.FmtSet{itemSep = ',\n', tblSep=''}, f)
  end
  f:close()
end

M.exe = function(t)
  for _, dir in ipairs(t) do
    M.makerock(dir)
  end
end

M.shim = shim{help = M.DOC, exe = M.exe}
return M
