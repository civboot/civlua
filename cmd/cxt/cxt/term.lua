-- cxt for the terminal, either plain text or vt100/etc
local M = assert(mod'cxt.term')
MAIN = MAIN or M

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

local KIND_ORDER = ds.BiMap {
  'hidden', 'table', 'list', 'br', 'quote',
  'code', 'block', 'name', 'path', 'clone',
  'h1', 'h2', 'h3', 'bold',
}


M.STYLES = {
  h1 = 'h1', h2 = 'h2', h3 = 'h3', h4 = 'h4',
  code = 'code', block = 'code', path = 'path',
  clone = 'var', name = 'api',
}

local function nodeKind(n)
  if type(n) == 'string' or mty.ty(n) == Token then
    return 'token'
  end
  for _, o in ipairs(KIND_ORDER) do
    if n[o] then return o end
  end
end

local function serializeRow(w, row, nl)
  w:incIndent(); if nl then push(w, '\n') end
  w:incIndent();
  for i, col in ipairs(row) do
    if i ~= 1 then push(w, '\t') end
    M.serialize(w, col)
  end
  w:decIndent(); w:decIndent()
end

local SER_KIND = {
  hidden = ds.noop,
  token = function(w, node) push(w, w:tokenStr(node)) end,
  br    = function(w, node) return push(w, '\n')      end,
  table = function(w, node)
    if #node == 0 then return end
    w:incIndent()
    for r, row in ipairs(node) do
      push(w, '\n+ ')
      -- if r == 1 then push(w, '  + ') else push(w, '\n+ ') end
      for c, col in ipairs(row) do
        if c ~= 1 then push(w, '\t') end
        w:incIndent(); M.serialize(w, col); w:decIndent()
      end
    end
    w:decIndent()
  end,
  list = function(w, node)
    w:incIndent()
    for _, item in ipairs(node) do
      push(w, '\n* ');
      w:incIndent(); M.serialize(w, item); w:decIndent()
    end
    w:decIndent()
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

  local prevSty = w.style
  w.style = M.STYLES[kind] or prevSty
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

-- Example: {'cxt to parse', out=file, mode='dark'}
M.main = function(args)
  args = shim.parseStr(args)
  local f = args.out or ds.popk(args, 2)
  if args.help or #args ~= 1 then
    local msg = 'Usage: cxt.term{"write [*to] stdout", to=io.stdout}'
    if M == MAIN then print(msg); os.exit(args.help and 0 or 1) end
    return args.help and msg or error(msg)
  end
  local inp = lines(args[1])
  if type(f) == 'string' then f = LFile:create(f) end
  local f = f or io.stdout
  local styler = style.Styler{
    f=f, color=shim.color(args.color, fd.isatty(f)),
    style = style.loadStyle(args.mode),
  }
  M.convert(inp, styler)
  return styler
end
getmetatable(M).__call = function(_, ...) return M.main(...) end

if M == MAIN then M.main(shim.parse(arg)); os.exit(0) end
return M
