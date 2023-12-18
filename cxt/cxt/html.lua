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
  if n.h1                    then return 'h1'  end
  if n.h2                    then return 'h2'  end
  if n.h3                    then return 'h3'  end
  for a in pairs(n) do if cxt.htmlAttr[a] then
    return 'div'
  end end
end
local function startFmt(n, line)
  for _, f in pairs(cxt.fmtAttr) do
    if n[f] then add(line, '<'..f..'>') end
  end
end
local function endFmt(n, line)
  for _, f in pairs(cxt.fmtAttr) do
    if n[f] then add(line, '</'..f..'>') end
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

local function addLine(out, line)
  ds.extend(out, ds.lines(table.concat(line)))
end

local function _serialize(p, out, line, node)
  local kind = nodeKind(node)
  if kind == 'token' then
    local s = p:tokenStr(node)
    if s:sub(#s,#s) == '\n' then
      add(line, s:sub(1, #s-1))
      mty.pnt('?? serialize line: ', line)
      addLine(out, line)
      line = {}
    else add(line, s) end
    return line
  elseif kind == 'br' then
    add(line, '<br>')
    addLine(out, line)
    return {}
  end
  mty.pnt('?? node kind='..tostring(kind)..':', node)
  startFmt(node, line)
  startNode(node, kind, line)
  if kind == 'ul' then
    addLine(out, line)
    for _, item in ipairs(node) do
      line = {'  <li>'}
      line = _serialize(p, out, line, item)
      add(line, '  </li>')
      addLine(out, line)
    end
    line = {}
  else
    for _, sub in ipairs(node) do
      line = _serialize(p, out, line, sub)
    end
  end
  endNode(node, kind, line); endFmt(node, line)
  return line
end
M.serialize = function(p, out, node)
  local line = {}; for _, n in ipairs(node) do
    line = _serialize(p, out, line, n)
  end
  if #line > 0 then addLine(out, line) end
end
M.serializeDoc = function(p, out, node)
  mty.pnt('?? serialize:', node)
  addLine(out, {'<!DOCTYPE html>\n<html><body>'})
  M.serialize(p, out, node)
  addLine(out, {'</body></html>'})
end

M.convert = function(dat, out)
  local out, node, p = out or {}, cxt.parse(dat)
  M.serializeDoc(p, out, node)
  return out, p
end

M.assertHtml = function(cxtDat, expectedHtml, dbg)
  local out, node, p = {}, cxt.parse(cxtDat, dbg)
  M.serialize(p, out, node)
  civtest.assertEq(expectedHtml, out)
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
    local out = df.LinesFile{io.open(args[2], 'w'), len=0}
    M.convert(inp, out)
    inp:close(); out:flush(); out:close()
  end,
})
M.shim = shim {
  help = 'Convert cxt doc to html',
  exe = M,
}

return M
