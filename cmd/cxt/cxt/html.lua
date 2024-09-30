--- Serialize cxt nodes as html
local M = mod and mod'cxt.html' or setmetatable({}, {})
MAIN = MAIN or M

local pkglib = require'pkglib'
local mty  = require'metaty'
local pegl = require'pegl'
local cxt  = require'cxt'
local shim = require'shim'
local civtest = require'civtest'
local push, sfmt = table.insert, string.format
local ds    = require'ds'
local lines = require'lines'
local LFile = require'lines.File'

local NAME_SYM = '☍'

M.htmlHead = [[<style>
h1 { margin-top: 0.5em; margin-bottom: 0.3em; }
h2 { margin-top: 0.3em; margin-bottom: 0.2em; }
h3 { margin-top: 0.2em; margin-bottom: 0.1em; }
h4 { margin-top: 0.1em; margin-bottom: 0.05em; }

p  { margin-top: 0.3em; margin-bottom: 0.0em; }
ul { margin-top: 0.1em; margin-bottom: 0.5em; }
li { margin-top: 0.1em; margin-bottom: 0.0em; }
blockquote {
  border: 1px solid #999;  border-radius: 0.1em;
  padding: 2px;            background-color: mintcream;
}
code {
  background-color: whitesmoke;
  border: 1px solid #999;  border-radius: 0.3em;
  font-family: Monaco, monospace;
  font-size: 14px;
  padding: 0px;
  white-space: pre
}
.block {
  margin-top: 0.1em;
  background-color: snow;  display: block;
  padding: 5px;
}
table, th, td {
    vertical-align: top;
    text-align: left;
    border-collapse: collapse;
    border: 1px solid grey;
    margin: 0.05em 0.05em;
    padding: 3px 5px;
}
table { min-width: 400px;         }
th    { background-color: LightCyan; }
td    { background-color: azure; }
</style>]]

local function nodeKind(n)
  if mty.ty(n) == pegl.Token then return 'token' end
  if n.code                  then return 'code'  end
  if n.table                 then return 'table' end
  if n.list                  then return 'ul'    end
  if n.br                    then return 'br'    end
end

local preNameAttrs = {'h1', 'h2', 'h3', 'h4', 'h5'}
local fmtAttrs = {'quote', 'b', 'i', 'u'}
local cxtRename = {quote='blockquote', name='id'}

local function addAttr(attrs, k, v)
  -- TODO: html encode
  push(attrs, sfmt('%s="%s"', k, v))
end

local noPKind = ds.Set{'ul', 'blockquote'}

local function addLine(w, line)
  ds.extend(w, lines(table.concat(line)))
end

local function startFmt(w, n, kind, line)
  for _, f in ipairs(preNameAttrs) do
    if n[f] then push(line, '<'..(cxtRename[f] or f)..'>') end
  end
  if n.name then
    push(line, sfmt('<a id="%s" href="#%s">%s</a>', n.name, n.name, NAME_SYM))
  end
  if n.href then
    push(line, '<a ')
    if n.id then addAttr(line, 'id', n.id) end
    addAttr(line, 'href', n.href)
    push(line, '>')
  elseif n.id then
    push(line, '<div '); addAttr(line, 'id', n.id); push(line, '>')
  end
  if n.path then
    push(line, '<a '); addAttr(line, 'href', w.config.pathUrl(n.path)); push(line, '>')
  end
  for _, f in ipairs(fmtAttrs) do
    if n[f] then push(line, '<'..(cxtRename[f] or f)..'>') end
  end
end
local function endFmt(n, line)
  for _, f in ds.ireverse(preNameAttrs) do
    if n[f] then push(line, '</'..(cxtRename[f] or f)..'>') end
  end
  for _, f in ds.ireverse(fmtAttrs) do
    if n[f] then push(line, '</'..(cxtRename[f] or f)..'>') end
  end
  if n.href then push(line, '</a>') end
  if n.path then push(line, '</a>') end
end
local function startNode(n, kind, line)
  if kind then
    push(line, '<'..kind)
    if n.block then push(line, ' class="block"')         end
    push(line, '>')
  end
end
local function endNode(n, kind, line)
  if not kind then return end
  push(line, '</'..kind..'>');
end

local CODE_REPL = {
  ['<'] = '&lt;',   ['>']  = '&gt;',
}

local function _serialize(w, line, node) --> line
  local kind = nodeKind(node)
  if kind == 'token' then
    local s = w:tokenStr(node)
    if s:sub(#s,#s) == '\n' then
      push(line, s:sub(1, #s-1))
      addLine(w, line)
      line = {}
    else push(line, s) end
    return line
  elseif node.hidden  then return line
  elseif kind == 'br' then
    push(line, '<p>'); addLine(w, line)
    return {}
  end
  startFmt(w, node, kind, line)
  startNode(node, kind, line)
  if kind == 'table' then
    addLine(w, line); w.indent = w.indent + 2
    for ri, row in ipairs(node) do
      addLine(w, {'<tr>'})
      for _, col in ipairs(row) do
        local el = row.header and 'th' or 'td'
        line = {'<'..el..'>'}
        line = _serialize(w, line, col)
        push(line, '</'..el..'>')
        addLine(w, line)
      end
      addLine(w, {'</tr>'})
    end
    line = {}; w.indent = w.indent - 2
  elseif kind == 'ul' then
    addLine(w, line); w.indent = w.indent + 2
    for _, item in ipairs(node) do
      line = {'<li>'}
      line = _serialize(w, line, item)
      push(line, '</li>')
      addLine(w, line)
    end
    line = {}; w.indent = w.indent - 2
  elseif node.code then
    local s = {}; for _, n in ipairs(node) do push(s, w:tokenStr(n)) end
    s = table.concat(s)
    if s:sub(1, 1) == '\n' then s = s:sub(2)    end
    if s:sub(-1)   == '\n' then s = s:sub(1,-2) end
    s = s:gsub('[&<>]', CODE_REPL)
    push(line, s)
  else
    for _, sub in ipairs(node) do
      line = _serialize(w, line, sub)
    end
  end
  endNode(node, kind, line); endFmt(node, line)
  return line
end

--- serialize the node to the writer.
M.serialize = function(w, node)
  -- line is an implementation detail of html around when to line break.
  -- We want to keep the output html as concise as reasonable, which
  -- this approach helps with.
  local line = {}; for _, n in ipairs(node) do
    line = _serialize(w, line, n)
  end
  if #line > 0 then
    addLine(w, line)
  end
end
M.serializeDoc = function(w, node, head)
  addLine(w, {'<!DOCTYPE html>\n<html><body>'})
  if head == nil then head = M.htmlHead end
  if head then addLine(w, {'<head>\n', head, '\n</head>'}) end
  M.serialize(w, node)
  addLine(w, {'</body></html>'})
end

M.convert = function(dat, to, config)
  local node, p = cxt.parse(dat)
  local w = cxt.Writer:fromParser(p, to)
  w.config = config or cxt.Config{}
  M.serializeDoc(w, node, w.config.header)
  return w.to, p, w
end

M.assertHtml = function(cxtDat, expectedHtml, dbg)
  local node, p = cxt.parse(cxtDat, dbg)
  local w = cxt.Writer:fromParser(p)
  M.serialize(w, node)
  civtest.assertEq(expectedHtml, w.to)
end

M.main = function(args)
  args = shim.parseStr(args)
  if #args < 2 then
    print'Usage: cxt path/to/file.cxt path/to/file.html'
    return 1
  end
  print('cxt.html', args[1], '-->', args[2])
  local inp = LFile(args[1])
  local to  = LFile(args[2], 'w+')
  if args.config then
    args.config = cxt.Config(pkglib.load('CxtConfig', args.config).html)
  end
  M.convert(inp, to, args.config)
  inp:close(); to:flush(); to:close()
  return 0
end

getmetatable(M).__call = function(_, args) return M.main(args) end
if M == MAIN then os.exit(M.main(arg)) end
return M
