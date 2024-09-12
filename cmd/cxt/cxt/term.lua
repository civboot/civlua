-- cxt for the terminal, either plain text or vt100/etc
local M = assert(mod'cxt.term')

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
  for i, col in ipairs(row) do
    if i ~= 1 then push(w, '\t') end
    M.serialize(w, col)
  end
  w:decIndent()
end

local SER_KIND = {
  hidden = ds.noop,
  token = function(w, node) push(w, w:tokenStr(node)) end,
  br    = function(w, node) return push(w, '\n')      end,
  table = function(w, node)
    local prevSty = w.style
    if #node == 0 then return end
    push(w, '  ')
    w.style = 'bold'; serializeRow(w, node[1]); w.style = prevSty
    for r=2,#node do serializeRow(w, node[r], true) end
  end,
  list = function(w, node)
    push(w, '\n')
    for _, item in ipairs(node) do
      push(w, '* '); M.serialize(w, item)
    end
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
getmetatable(M).__call = function(_, args, isExe) --> Styler
  local inp = lines(args[1])
  local f = args[2] or args.out
  if type(f) == 'string' then f = LFile:create(f) end
  local f = f or io.stdout
  local styler = style.Styler{
    f=f, color=shim.color(args.color, fd.isatty(f)),
    style = style.loadStyle(args.mode),
  }
  M.convert(inp, styler)
  return styler
end

M.shim = shim {
  help = 'print cxt doc to terminal',
  exe = M,
}

return M
