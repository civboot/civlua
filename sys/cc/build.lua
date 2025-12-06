local mty  = require'metaty'

--- C compiler for civ build.
local M = mty.mod'sys:cc.build'
assert(not G.MAIN, 'must be run as main')
G.MAIN = M

local ds = require'ds'
local ix = require'civix'
local T  = require'civtest'

local push = ds.push

local b = require'civ.Builder':get()
io.stderr:write'cc builder starting\n'

local function pushLibs(cmd, tgt)
  if tgt.out.lib then
    push(cmd, '-l'..assert(tgt.out.lib:match'lib([%w_]+)%.so'))
  end
  for _, id in ipairs(tgt.dep) do
    pushLibs(cmd, b:target(id))
  end
end

for _, id in ipairs(b.ids) do
  local tgt = b:target(id)
  io.stderr:write('cc building target: ', tgt:tgtname(), '\n')
  ix.mkDirs(b.cfg.buildDir..'lib')
  b:copyOut(tgt, 'include')
  local lib = tgt.out.lib; if lib then
    local cmd = {'cc'}
    for _, src in ipairs(tgt.src) do push(cmd, tgt.dir..src) end
    -- TODO: needs to come from sys:lua.
    push(cmd, '-llua')
  
    ds.extend(cmd, {'-fPIC', '-I'..b.cfg.buildDir..'include'})
    for _, dep in ipairs(tgt.dep or EMPTY) do pushLibs(cmd, dep) end
    push(cmd, '-shared')
    lib = b.cfg.buildDir..'lib/'..lib
    ds.extend(cmd, {'-o', lib})
    ix.sh(cmd)
    T.exists(lib)
  end
end
