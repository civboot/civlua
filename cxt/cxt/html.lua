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

M.htmlHead = [[<style>
p  { margin-top: 0.5em; margin-bottom: 0.0em; }
ul { margin-top: 0.0em; margin-bottom: 0.5em; }
li { margin-top: 0.0em; margin-bottom: 0.0em; }
blockquote {
  border: 1px solid #999;  border-radius: 0.1em;
  padding: 5px;            background-color: mintcream;
}
code {
  background-color: whitesmoke;
  border: 1px solid #999;  border-radius: 0.3em;
  font-family: Monaco, monospace;
  padding: 0px;
  white-space: pre
}
.block {
  margin-top: 0.5em;
  background-color: snow;  display: block;
  padding: 5px;
}</style>]]

local function nodeKind(n)
  if mty.ty(n) == pegl.Token then return 'token' end
  if n.code                  then return 'code'  end
  if n.list                  then return 'ul'    end
  if n.br                    then return 'br'    end
end

local fmtAttrs = {'quote', 'h1', 'h2', 'h3', 'b', 'i', 'u'}
local cxtRename = {quote='blockquote'}

local function addAttr(attrs, k, v)
  -- TODO: html encode
  add(attrs, sfmt('%s="%s"', k, v))
end

local noPKind = ds.Set{'ul', 'blockquote'}

local function addLine(w, line)
  ds.extend(w, ds.lines(table.concat(line)))
end

local function startFmt(w, n, kind, line)
  if n.href then
    add(line, '<a '); addAttr(line, 'href', n.href); add(line, '>')
  end
  for _, f in ipairs(fmtAttrs) do
    if n[f] then add(line, '<'..(cxtRename[f] or f)..'>') end
  end
end
local function endFmt(n, line)
  for _, f in ds.ireverse(fmtAttrs) do
    if n[f] then add(line, '</'..(cxtRename[f] or f)..'>') end
  end
  if n.href then add(line, '</a>') end
end
local function startNode(n, kind, line)
  if not kind then return end
  add(line, '<'..kind)
  if n.block then add(line, ' class="block"') end
  add(line, '>')
end
local function endNode(n, kind, line)
  if not kind then return end
  add(line, '</'..kind..'>');
end

local CODE_REPL = {
  -- [' '] = '&nbsp;', ['\n'] = '<br>\n', ['\t'] = '&Tab;',
  ['<'] = '&lt;',   ['>']  = '&gt;',
}

local function _serialize(w, line, node)
  local kind = nodeKind(node)
  mty.pnt('?? node kind', sfmt('%q', kind), node)
  if kind == 'token' then
    local s = w:tokenStr(node)
    if s:sub(#s,#s) == '\n' then
      add(line, s:sub(1, #s-1))
      mty.pnt('?? serialize line: ', line)
      addLine(w, line)
      line = {}
    else add(line, s) end
    return line
  elseif node.hidden  then return line
  elseif kind == 'br' then
    add(line, '<p>'); addLine(w, line)
    return {}
  end
  mty.pnt('?? node kind='..tostring(kind)..':', node)
  startFmt(w, node, kind, line)
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
  elseif node.code then
    assert(#node == 1)
    local s = w:tokenStr(node[1])
    if s:sub(1, 1) == '\n' then s = s:sub(2) end
    mty.pnt('?? node.code token:', s)
    s = s:gsub('[&<>]', CODE_REPL)
    mty.pnt('?? node.code after gsub:', s)
    add(line, s)
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
  if #line > 0 then
    addLine(w, line)
  end
end
M.serializeDoc = function(w, node, head)
  mty.pnt('?? serialize:', node)
  addLine(w, {'<!DOCTYPE html>\n<html><body>'})
  if head == nil then head = M.htmlHead end
  if head then addLine(w, {'<head>\n', head, '\n</head>'}) end
  M.serialize(w, node)
  addLine(w, {'</body></html>'})
end

M.convert = function(dat, to, head)
  local node, p = cxt.parse(dat)
  local w = cxt.Writer:fromParser(p, to)
  M.serializeDoc(w, node, head)
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
