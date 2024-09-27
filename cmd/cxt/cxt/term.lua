G = G or _G
--- cxt for the terminal, either plain text or vt100/etc
local M = mod'cxt.term'
MAIN = G.MAIN or M

local mty  = require'metaty'
local ds = require'ds'
local shim = require'shim'
local pegl = require'pegl'
local cxt  = require'cxt'
local style = require'asciicolor.style'
local fd = require'fd'
local log = require'ds.log'
local lines = require'lines'
local LFile = require'lines.File'

local Token = assert(require'pegl'.Token)
local push = table.insert

--- Render cxt on a terminal.
---
--- Will render an input string or --inp=file.
M.Args = mty'Args' {
  'inp  [path|file]: input file',
  'out  [path|file]: output file (default=stdout)',
}

local KIND_ORDER = ds.BiMap {
  'hidden', 
  'table', 'list', 'quote',

  'h1', 'h2', 'h3', 'h4',
  'br', 'code', 'block', 'name', 'path', 'clone',
  'b', 'u', 'class',
}

M.STYLES = {
  h1 = 'h1', h2 = 'h2', h3 = 'h3', h4 = 'h4',
  code = 'code', block = 'code', path = 'path',
  clone = 'var', name = 'api',
  b = 'bold', u='ul',
}

M.HEADER = {h1=40, h2=20, h3=5, h4=1}

local function nodeKind(n)
  if type(n) == 'string' or mty.ty(n) == Token then
    return 'token'
  end
  for _, o in ipairs(KIND_ORDER) do
    if n[o] then return o end
  end
end

local function serializeRow(w, row, nl)
  w:level(1); if nl then push(w, '\n') end
  w:level(1);
  for i, col in ipairs(row) do
    if i ~= 1 then push(w, '\t') end
    M.serialize(w, col)
  end
  w:level(-1); w:level(-1)
end

local SER_KIND = {
  hidden = ds.noop,
  token = function(w, node) push(w, w:tokenStr(node)) end,
  br    = function(w, node) return push(w, '\n')      end,
  table = function(w, node)
    if #node == 0 then return end
    w:level(1)
    for r, row in ipairs(node) do
      push(w, '\n+ ')
      -- if r == 1 then push(w, '  + ') else push(w, '\n+ ') end
      for c, col in ipairs(row) do
        if c ~= 1 then push(w, '\t') end
        w:level(1); M.serialize(w, col); w:level(-1)
      end
    end
    w:level(-1)
  end,
  list = function(w, node)
    w:level(1)
    for _, item in ipairs(node) do
      push(w, '\n* ');
      w:level(1); M.serialize(w, item); w:level(-1)
    end
    w:level(-1)
  end,
  code = function(w, node)
    local prevSty = w.style
    local s = {}; for _, n in ipairs(node) do push(s, w:tokenStr(n)) end
    s = table.concat(s)
    if node.block and s:sub(-1) == '\n' then
      s = s:sub(1, -2) -- strip extra newline
    end
    w.style = 'code'; push(w, s); w.style = prevSty
  end,
}
SER_KIND.block = SER_KIND.code

-- serialize node to a writer
M.serialize = function(w, node)
  local kind = nodeKind(node)
  local fn = SER_KIND[kind]
  if fn then return fn(w, node) end
  local header = M.HEADER[kind]
  local prevSty = w.style
  if header then
    w.style = 'meta'; push(w, string.rep('#', header))
    if header > 4 then push(w, '\n# ') else push(w, ' ') end
  end

  w.style = M.STYLES[kind] or node.style or prevSty
  for _, n in ipairs(node) do M.serialize(w, n) end
  w.style = prevSty
end

M.convert = function(dat, to)
  if type(dat) == 'string' then dat = lines(dat) end
  local node, p = cxt.parse(dat)
  local w = cxt.Writer:fromParser(p, to)
  M.serialize(w, node)
  return w, node, p
end

M.main = function(args)
  args = M.Args(shim.parseStr(args))
  args.out = args.out or io.fmt
  if #args > 0    then args.inp = lines(table.concat(args, ' '))
  elseif args.inp then args.inp = LFile:create(shim.file(args.inp))
  else error'must provide input' end
  M.convert(args.inp, args.out)
  args.out:write'\n'
  return args.out
end
getmetatable(M).__call = function(_, ...) return M.main(...) end

if M == MAIN then M.main(shim.parse(arg)); os.exit(0) end
return M
