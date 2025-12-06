local mty = require'metaty'
local G = mty.G

local shim = require'shim'
local Iter = require'ds.Iter'
local fmt = require'fmt'
local ds = require'ds'
local dload = require'ds.load'
local info = require'ds.log'.info
local pth = require'ds.path'
local lson = require'lson'
local ix = require'civix'
local core = require'civ.core'
local File = require'lines.File'
local forceLoadIdx = require'lines.futils'.forceLoadIdx

local sfmt = string.format
local push, pop = ds.push, table.remove
local EMPTY = {}

local BUILDER -- single instance

--- civ Builder object.
--- Parses the arguments passed during [$civ build] and
--- allows deserializing any referenced targets by id from an indexed file.
local Builder = mty'civ.Builder' {
  'ids {int}: the target ids to build.',
  'cfg [civ.core.Cfg]',
  'tgtsDb [lines.File]: indexed line-file of targets by id',
  'targets [id -> Target]: already loaded targets',
}
getmetatable(Builder).__call = function(T, self)
  fmt.print('creating Builder:', self)
  assert(self.ids,    'must set ids')
  assert(self.cfg,    'must set cfg')
  assert(self.tgtsDb, 'must set tgtsDb')
  self.targets = self.targets or {}
  self = mty.construct(T, self)
  return self
end

--- Usage: [$builder = Builder:get()]
Builder.get = function(T, args)
  if BUILDER then return BUILDER end
  args = args or G.arg
  args = shim.parse(args)
  fmt.print('parsing Builder from args:', args)
  local ids = {}
  local ids = Iter:ofList(args):mapV(math.tointeger):to()
  assert(#ids > 0, 'must specify at least one id to build')
  local ok, cfg = dload(assert(args.config, '--config not set'))
  assert(ok, cfg)
  BUILDER = T {
    ids = ids,
    cfg = cfg,
    tgtsDb = assert(File {
      path = assert(args.tgtsDb, '--tgtsDb not set'),
      mode = 'r',
      loadIdxFn = forceLoadIdx,
    }),
  }
  return BUILDER
end

function Builder:target(id) --> Target
  local tgt = self.targets[id]; if tgt then return tgt end
  tgt = core.Target(lson.decode(self.tgtsDb:get(id)))
  self.targets[id] = tgt
  return tgt
end


--- Copy output files from [$tgt.out[outKey]].
function Builder:copyOut(tgt, outKey)
  if not tgt.out[outKey] then return nil, 'missing out: '..outKey end
  local F, T = tgt.dir, self.cfg.buildDir..outKey..'/'
  for from, to in pairs(tgt.out[outKey]) do
    if type(from) == 'number' then from = to end
    to = T..to; fmt.assertf(not ix.exists(to), 'to %q already exists', to)
    from = F..from
    fmt.assertf(ix.exists(from), 'src %q does not exists', from)
    ix.forceCp(from, to)
  end
  return true
end

--- Make self the singleton (future calls to Builder.get will return)
function Builder:set() BUILDER = self; return self end

--- Remove this as singleton.
function Builder:close() BUILDER = nil               end

return Builder
