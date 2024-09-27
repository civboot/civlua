-- TODO:
--   [1Header block]
local M = mod and mod'cxt' or {}

local pkg = require'pkglib'
local mty = require'metaty'
local fmt = require'fmt'
local ds  = require'ds'; local lines = require'lines'
local civtest = require'civtest'
local add, sfmt = table.insert, string.format

local Key
local Pat, Or, Not, Many, Maybe
local Token, Empty, Eof, PIN, UNPIN
local EMPTY, common
local pegl = ds.auto'pegl'

local RAW = '#'

--- escape the string so it renders literally
M.escape = function(str) return str:gsub('([\\%[%]])', '\\%1') end

------------------------
-- Parsing
-- The only thing PEGL is leveraged for is parsing the attributes because
-- that is whitespace agnostic.  Otherwise whitespace is VERY important
-- in cxt, and handling whitespace in PEGL would be a complete hack.

M.attrSym = Key{kind='attrSym', {
  '!',             -- hidden
  '*', '/', '_',   -- bold, italic, underline
  ':',             -- define node name
}}
M.keyval = {kind='keyval',
  Pat'[_.%-%w]+',
  Maybe{'=', Pat'[^%s{}]+', kind='value'},
}
M.attr  = Or{Pat{RAW..'+', kind='raw'}, M.attrSym, M.keyval}
M.attrs =   {PIN, Many{M.attr}, '}', kind='attrs'}

local function addToken(p, node, l1, c1, l2, c2)
  if l2 >= l1 and (l2>l1 or c2>=c1) then
    add(node, Token:encode(p, l1, c1, l2, c2))
  end
end

local function nodeText(p, node, errNode)
  local txt = {}; for _, t in ipairs(node) do
    if mty.ty(t) ~= Token then
      p.c, p.l = (errNode or t).pos
      p:error(sfmt('text must be of node with only strings %q', ctrl))
    end
    add(txt, p:tokenStr(t))
  end
  return table.concat(txt)
end

--- find the end of a [$[##raw block]##]
local function bracketedStrRaw(p, node, raw, ws)
  node.code = node.code or (node.lang and true)
  local ws, w1 = p.line:find'^%s+' -- leading whitespace
  ws = ws and p.line:sub(ws, w1) or nil
  local l, c, closePat = p.l, p.c, '%]'..string.rep(RAW, raw)
  local closePatStart = '^'..closePat
  if p.c > #p.line then p:incLine() end
  while true do
    if p:isEof() then p:error(sfmt(
      "Got EOF, expected %q", closePat:sub(2)
    ))end
    if ws and p.c == 1 then -- strip leading whitespace
      addToken(p, node, l, c, p.l, p.c - 1)
      local w1, w2 = p.line:find(ws); if w1 ~= 1 then
        p:error(sfmt('Expected leading %q', ws))
      end
      l, c, p.c = p.l, w2+1, w2+1
    end
    local c1, c2 = p.line:find(closePat, p.c)
    if c2 then
      p.c = c2 + 1; local lt, ct = p.l, c1 - 1
      return addToken(p, node, l, c, lt, ct) --> nil
    end
    p:incLine(); node.block = true
    ::continue::
  end
end

--- A string that ends in a closed bracket and handles balanced brackets.
--- Returns: Token, which does NOT include the closePat
local function bracketedStr(p, node, raw)
  if raw > 0 then return bracketedStrRaw(p, node, raw) end
  local l, c, nested = p.l, p.c, 1
  while nested > 0 do
    if p:isEof()     then p:error"Got EOF, expected matching ']'" end
    if p.c > #p.line then p:incLine(); goto continue end
    local c1, c2 = p.line:find('[%[%]]', p.c); if c2 then
      if p.line:sub(c1,c2) == '[' then p.c = c2 + 1; nested = nested + 1
      else                             p.c = c2 + 1; nested = nested - 1 end
    else p:incLine() end
    ::continue::
  end
  add(node, Token:encode(p, l, c, p.l, p.c - 2))
end

local fmtAttr = {
  ['*'] = 'b', [','] = 'i', ['_'] ='u',
  ['"'] = 'quote',
  [':'] = 'name', -- both here and txtCtrl. This sets node.name=true
}
local strAttr = {
  ['!'] = 'hidden',   ['$'] = 'code',
}
local txtCtrl = {[':'] = 'name', ['@'] = 'clone', ['/'] = 'path'}
local shortAttrs = {n='name', v='value'}

local function parseAttrs(p, node)
  local l, c, raw = p.l, p.c, nil
  local attrs = p:parse(M.attrs)
  for _, attr in ds.islice(attrs, 1, #attrs-1) do
    if attr.kind == 'attrSym' then
      local attr = p:tokenStr(attr)
      node[assert(fmtAttr[attr] or strAttr[attr])] = true
    elseif attr.kind == 'keyval' then
      local val = attr[2]
      val = (val == pegl.EMPTY) and true or p:tokenStr(val[2])
      node[p:tokenStr(attr[1])] = val
    else
      fmt.assertf(attr.kind == 'raw', 'kind: %s', attr.kind)
      if raw then
        p.l, p.c = l, c; p:error'multiple raw (##...) attributes'
      end
      local _, c1, _, c2 = attr:span()
      raw = c2 - c1 + 1
    end
  end
  return raw
end

local ITEM = {
  ['^%s*%* ']      = 'bullet',
  ['^%s*%(%d+%) '] = 'numbered',
}

local LIST_ITEM_ERR = [[
expected bullet item followed by whitespace. Examples:\n
      *   bullet
      (1) numbered
      [ ] unchecked
      [x] checked
]]
local function parseList(p, list)
  p:skipEmpty()
  if p:isEof() then p:error'Expected a list got EOF' end
  local ipat, ikind; for ip, i in pairs(ITEM) do
    if p:consume(ip) then ipat, ikind = ip, i
      break
    end
  end
  if not ipat then p:error(LIST_ITEM_ERR) end
  local altEnd = function(p, node, l, c)
    local c1, c2 = p.line:find(ipat)
    if c2 and (p.c <= c2) then return {l, c} end
  end
  while true do
    local item = {}
    local r = M.content(p, item, false, altEnd)
    if r then
      addToken(p, item, r[1], r[2], p.l, p.c - 1)
      local c1, c2 = p.line:find(ipat, p.c)
      p.c = c2 + 1
    end
    p:trimTokenLast(item, true)
    add(list, item)
    if not r then break end
  end
end

local function parseTable(p, tbl)
  if p.line and p.c > #p.line then p:incLine() end
  local rowDel, headDel, colDel = tbl.row or '+', tbl.head or '#', tbl.col or '|'
  local rowStart = {[rowDel]=true, [headDel]=true}

  -- alternative end lambda
  local altEnd = function(p, node, l, c)
    if not p.line:sub(1, p.c-1):find'%S' then -- only parsed ws
      local _, c2 = p.line:find'%S'           -- look for row start
      if c2 and rowStart[p.line:sub(c2,c2)] then return {p.line:sub(c2,c2), l, c} end
    end
    local c1, c2 = p.line:find(colDel, p.c, true); if not c1 then return end
    local b1, b2 = p.line:find('[', p.c, true)
    if not b1 or b1 > c1 then return {colDel, l, c} end
  end

  local r, content, row = 1
  repeat
    if p:isEof() then p:error'Expected a table got EOF' end
    local col = {}; content = M.content(p, col, false, altEnd)
    if not content then
      if row and #col > 0 then add(row, col) end
      break
    end
    local delim, l, c = table.unpack(content)
    local c1, c2 = p.line:find(delim, p.c, true)
    if delim == colDel then
      addToken(p, col, l, c, p.l, c1 - 1)
    else assert(rowStart[delim])
      addToken(p, col, l, c, p.l - 1, #p.dat[p.l - 1])
    end
    p.c = c2 + 1
    if row then add(row, col) end
    if rowStart[delim] then -- save current row and start the next row
      if row then add(tbl, row) end
      row = {}
      if delim == rowDel then        row.row = r; r = r + 1
      else                           row.header = true end
    end
  until not content
  if row and #row > 0 then add(tbl, row) end
  for _, row in ipairs(tbl) do
    for c, col in ipairs(row) do
      p:trimTokenStart(col)
      p:trimTokenLast(col, c == #row)
    end
  end
end

--- skip whitespace, return whether it was skipped
local function skipWs(p)
  if not p.line then return end
  p.c = select(2, p.line:find('%S', p.c)) or #p.line + 1
end

--- increment line, adding token and skipping next line's whitespace.
--- include newline in token unless this line is EOF
local function incLine(p, node, l1, c1)
  local l2, c2 = p.l, #p.line
  if l1 ~= #p.dat then l2, c2 = l2 + 1, 0 end
  addToken(p, node, l1, c1, l2, c2)
  p:incLine(); skipWs(p)
  return p.l, p.c
end

--- parse normal content, adding to node
M.content = function(p, node, isRoot, altEnd)
  local l, c = p.l, p.c
  ::loop::
  if p.line == nil then
    if not isRoot then error(
      "! ERROR on input:\n\n"
       ..table.concat(p.dat, '\n')
       .."\n\n! Error: Expected ']' but reached end of file"
    )
    end
    return addToken(p, node, l, c, p.l - 1, #p.dat[p.l - 1]) --> nil
  elseif #p.line == 0 and p.dat[l+1] then
    add(node, {pos={l}, br=true})
    p:incLine(); skipWs(p); l, c = p.l, p.c
    goto loop
  elseif p.c > #p.line then l, c = incLine(p, node, l, c); goto loop end
  if altEnd then
    local e = altEnd(p, node, l, c); if e then return e end
  end
  ::refind::
  local c1, c2 = p.line:find('\\?[%[%]\\]', p.c); if not c2 then
    l, c = incLine(p, node, l, c)
    goto loop
  end
  p.c = c2 + 1
  if c1 ~= c2 then -- \escaped
    addToken(p, node, l, c, p.l, c1-1)
    c = c2; goto loop
  end
  -- found unescaped syntax character: [ ] \
  if p.line:sub(c2,c2) == '\\' then goto refind end -- '\*' --> '\*'
  addToken(p, node, l, c, p.l, c2-1)
  local posL, posC = p.l, p.c
  if p.line:sub(c1,c2) == ']' then return end -- end of this content
  local raw, ctrl = nil, p.line:sub(p.c, p.c)
  if ctrl == '' then
    p:error("expected control char after '['")
  elseif ctrl == RAW then
    local c1, c2 = p.line:find('^#+', p.c)
    assert(c2)
    p.c, raw = c2 + 1, c2 - c1 + 1
  end
  p.c = p.c + 1
  local sub = {}
  if     raw           then sub.raw, sub.code       = raw, true
  elseif txtCtrl[ctrl] then -- handled after content
  elseif fmtAttr[ctrl] then sub[fmtAttr[ctrl]]      = true
  elseif strAttr[ctrl] then sub[strAttr[ctrl]], raw = true, 0
  elseif ctrl == '+'   then sub.list                = true
  elseif ctrl == '{'   then raw = parseAttrs(p, sub)
  elseif ctrl == '<' then
    sub.href = p:tokenStr(assert(p:parse{PIN, Pat'[^>]*', '>'}[1]))
  else p:error(sfmt( "Unrecognized control character after '[': %q", ctrl)) end
  -- parse table depending on kind
  if raw           then bracketedStr(p, sub, raw)
  elseif sub.table then parseTable(p, sub)
  elseif sub.list  then parseList(p, sub)
  else                  M.content(p, sub) end
  -- clean up attributes
  local txtAttr = txtCtrl[ctrl] or (sub.name == true) and 'name'
  if txtAttr then
    sub[txtAttr] = nodeText(p, sub):gsub('%s', '_')
  end
  for s, a in pairs(shortAttrs) do
    if sub[s] then sub[a] = sub[s]; sub[s] = nil end
  end
  sub.pos = {posL,posC,p.l,p.c-1}
  add(node, sub)
  l, c = p.l, p.c
  goto loop
end

local function extractNamed(node, named)
  if rawget(node, 'name') then
    if named[node.name] then
      local l, c = table.unpack(named[node.name].pos)
      error(sfmt('ERROR node %q is named twice: %s.%s and %s.%s',
        node.name, l, c, table.unpack(node.pos)))
    end
    named[node.name] = node
  end
  for _, n in ipairs(node) do
    if mty.ty(n) ~= Token then extractNamed(n, named) end
  end
end

local function getNamed(node, named, name)
  local n = named[name]; if not n then
   local l, c = node.pos; error(sfmt(
     'ERROR %s.%s: name %q not found', l, c, name))
  end
  return n
end

local function resolveFetches(p, node, named)
  local nty = mty.ty(node)
  if nty == Token or nty == 'string' then return node end
  if node.clone then
    local n = named[node.clone]; if n then
      local n = ds.copy(n)
      n.hidden, n.name, n.value = nil, nil, nil
      return n
    else return node end
  end
  -- replace all @attr values
  for k, v in pairs(node) do
    if type(k) ~= 'number' and type(v) == 'string' and v:sub(1,1) == '@' then
      local n = named[v:sub(2)]; if n then
        local attr = n.value or (n.href and 'href') or 'text'
        if attr == 'text' then v = nodeText(p, n, v)
        else                   v = n[attr] end
        node[k] = v
      end
    end
  end
  for i, n in ipairs(node) do node[i] = resolveFetches(p, n, named) end
  return node
end

M.parse = function(dat, dbg)
  local p = pegl.Parser:new(dat, pegl.RootSpec{dbg=dbg})
  skipWs(p)
  local root, named = {}, {}
  M.content(p, root, true)
  extractNamed(root, named)
  resolveFetches(p, root, named)
  return root, p
end

---------------------------
-- Testing Helpers

local SKIP_FOR_STR = ds.Set{'pos', 'raw'}
M.parsedStrings = function(p, node)
  if type(node) ~= 'table' then return node end
  if mty.ty(node) == Token then return p:tokenStr(node) end
  local n = {}
  for k, v in pairs(node) do
    if not SKIP_FOR_STR[k] then
      v = M.parsedStrings(p, v)
      n[k] = v
    end
  end
  return n
end

M.assertParse = function(dat, expected, dbg) --> node
  local node, p = M.parse(dat, dbg)
  node = M.parsedStrings(p, node)
  civtest.assertEq(expected, node)
  return node
end

M.fmtAttr = fmtAttr
M.htmlFmt  = ds.Set{'b', 'i', 'u'}

--- A Writer for cxt serializers (terminal, http, etc) to use.
---
--- The writer contains: [+
--- * The src lines and token decoder for getting pegl.Token values.
--- * The destination lines and current indent level.
--- ]
M.Writer = mty'Writer' {
  'src', 'to',
  'indent[int]',
  'style [string]: see asciicolor.style',
}
M.Writer.fromParser = function(ty_, p, to)
  return ty_{src=p.dat, to=to or {}, indent=0}
end
M.Writer.tokenStr = function(w, t)
  return (type(t) == 'string') and t or t:decode(w.src)
end
M.Writer.__index = function(w, l)
  local m = getmetatable(w)[l]; if m then return m end
  if type(l) ~= 'number' then return end
  fmt.errorf('index cxt.Writer: %s', l)
end
M.Writer.__newindex = function(w, l, line)
  if type(l) ~= 'number' then return rawset(w, l, line) end
  if w.style then w.to:styled(w.style, line)
  else            w.to[l] = line end
end
M.Writer.__len = function(w) return #w.to end
M.Writer.level = function(w, add) return w.to:level(add) end

return M
