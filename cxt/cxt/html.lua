local DOC = "Serialize cxt nodes as html"
local mty  = require'metaty'
local pegl = require'pegl'
local cxt  = require'cxt'
local shim = require'shim'
local civtest = require'civtest'
local add, sfmt = table.insert, string.format
local ds = require'ds'; local lines = ds.lines
local df = require'ds.file'

local M = mty.docTy({}, DOC)

local function nodeKind(n)
  if mty.ty(n) == pegl.Token then return 'token' end
  if n.code                  then return 'pre' end
  if n.list                  then return 'ul' end
  if n.br                    then return 'br'  end
  for a in pairs(n) do if cxt.htmlAttr[a] then
    return 'div'
  end end
end

local fmtAttrs = {'quote', 'h1', 'h2', 'h3', 'b', 'i', 'u'}
local cxtRename = {quote='blockquote'}

local function startFmt(n, line)
  for _, f in ipairs(fmtAttrs) do
    if n[f] then add(line, '<'..(cxtRename[f] or f)..'>') end
  end
end
local function endFmt(n, line)
  for _, f in ds.ireverse(fmtAttrs) do
    if n[f] then add(line, '</'..(cxtRename[f] or f)..'>') end
  end
end
local function startNode(n, kind, line)
  if not kind then return end
  add(line, '<')
  local attrs = {kind}
  for k in pairs(cxt.htmlAttr) do
    if n[k] then
      -- TODO: html encode
      add(attrs, sfmt('%s="%s"', k, n[k]))
    end
  end
  add(line, table.concat(attrs, ' '))
  add(line, '>')
end
local function endNode(n, kind, line)
  if not kind then return end
  add(line, '</'..kind..'>');
end

local function addLine(w, line)
  ds.extend(w, ds.lines(table.concat(line)))
end

local function _serialize(w, line, node)
  local kind = nodeKind(node)
  if kind == 'token' then
    local s = w:tokenStr(node)
    if s:sub(#s,#s) == '\n' then
      add(line, s:sub(1, #s-1))
      mty.pnt('?? serialize line: ', line)
      addLine(w, line)
      line = {}
    else add(line, s) end
    return line
  elseif node.hidden  then return
  elseif kind == 'br' then
    add(line, '<br>')
    addLine(w, line)
    return {}
  end
  mty.pnt('?? node kind='..tostring(kind)..':', node)
  startFmt(node, line)
  startNode(node, kind, line)
  if kind == 'ul' then
    addLine(w, line); w.indent = w.indent + 2
    for _, item in ipairs(node) do
      line = {'<li>'}
      line = _serialize(w, line, item)
      add(line, '</li>')
      addLine(w, line)
    end
    line = {}; w.indent = w.indent - 2
  else
    for _, sub in ipairs(node) do
      line = _serialize(w, line, sub)
    end
  end
  endNode(node, kind, line); endFmt(node, line)
  return line
end
M.serialize = function(w, node)
  local line = {}; for _, n in ipairs(node) do
    line = _serialize(w, line, n)
  end
  if #line > 0 then addLine(w, line) end
end
M.serializeDoc = function(w, node)
  mty.pnt('?? serialize:', node)
  addLine(w, {'<!DOCTYPE html>\n<html><body>'})
  M.serialize(w, node)
  addLine(w, {'</body></html>'})
end

M.convert = function(dat, to)
  local node, p = cxt.parse(dat)
  local w = cxt.Writer:fromParser(p, to)
  M.serializeDoc(w, node)
  return w.to, p, w
end

M.assertHtml = function(cxtDat, expectedHtml, dbg)
  local node, p = cxt.parse(cxtDat, dbg)
  local w = cxt.Writer:fromParser(p)
  M.serialize(w, node)
  civtest.assertEq(expectedHtml, w.to)
end

M.Args = mty.doc[[Convert cxt doc to html]]
(mty.record'Html')
  :field('cxt', 'string'):fdoc'path to cxt file'
  :field('out', 'string'):fdoc'path to html file output'

setmetatable(M, {
  __call = function(_, args, isExe)
    mty.pnt('?? html args:', args, 'isExe:', isExe)
    local inp = df.LinesFile{
      io.open(args[1]), cache=10,
      len=df.readLen(args[1]),
    }
    local to = df.LinesFile{io.open(args[2], 'w'), len=0}
    M.convert(inp, to)
    inp:close(); to:flush(); to:close()
  end,
})
M.shim = shim {
  help = 'Convert cxt doc to html',
  exe = M,
}

return M
