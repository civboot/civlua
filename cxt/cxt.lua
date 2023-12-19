-- TODO:
--   ["quote block]
--   [1Header block]

local mty = require'metaty'
local ds  = require'ds'; local lines = ds.lines
local civtest = require'civtest'
local add, sfmt = table.insert, string.format

local Key
local Pat, Or, Not, Many, Maybe
local Token, Empty, Eof, PIN, UNPIN
local EMPTY, common
local pegl = mty.lrequire'pegl'

local M = {}
local RAW = '#'

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

-- find the end of a [##raw block]##
local function bracketedStrRaw(p, raw)
  local l, c, closePat = p.l, p.c, '%]'..string.rep(RAW, raw)
  while true do
    if p:isEof() then p:error(sfmt(
      "Got EOF, expected %q", closePat:sub(2)
    ))end
    local c1, c2 = p.line:find(closePat, p.c)
    if c2 then
      p.c = c2 + 1
      local lt, ct = p.l, c1 - 1
      -- if ct == 0 then
      --   -- ignore last newline if end is at start
      --   lt, ct = p.l - 1, #p.dat[p.l - 1]
      -- end
      return Token:encode(p, l, c, lt, ct)
    end
    p:incLine()
  end
end

-- A string that ends in a closed bracket and handles balanced brackets.
-- Returns: Token, which does NOT include the closePat
local function bracketedStr(p, raw)
  mty.pntf('?? bracketedStr %s %s.%s: %s', raw, p.l, p.c, p.line:sub(p.c))
  if raw > 0 then return bracketedStrRaw(p, raw) end
  local l, c, nested = p.l, p.c, 1
  while nested > 0 do
    if p:isEof() then p:error"Got EOF, expected matching ']'" end
    if p.c > #p.line then p:incLine(); goto continue end
    local c1, c2 = p.line:find('[%[%]]', p.c); if c2 then
      if p.line:sub(c1,c2) == '[' then
        p.c = c2 + 1; nested = nested + 1
      else
        p.c = c2 + 1; nested = nested - 1
      end
    end
    ::continue::
  end
  return Token:encode(p, l, c, p.l, p.c - 2)
end

local fmtAttr = {
  ['*'] = 'b', ['/'] = 'i', ['_'] ='u',
  ['"'] = 'quote',
}
local strAttr = {
  ['!'] = 'hidden',   ['$'] = 'code',
  ['.'] = 'path',     ['@'] = 'fetch',
}

local function parseAttrs(p, node)
  local l, c, raw = p.l, p.c, nil
  print('?? attrs:', p.line:sub(c))
  local attrs = p:parse(M.attrs)
  for _, attr in ds.islice(attrs, 1, #attrs-1) do
    mty.pnt('?? attr:', attr)
    if attr.kind == 'attrSym' then
      mty.pnt('?? attrSym:', attr, mty.ty(attr))
      local attr = p:tokenStr(attr)
      mty.pnt('?? attrSym:', attr)
      node[assert(fmtAttr[attr] or strAttr[attr])] = true
    elseif attr.kind == 'keyval' then
      local val = attr[2]
      if val == pegl.EMPTY then val = true
      else                      val = p:tokenStr(val[2]) end
      node[p:tokenStr(attr[1])] = val
    else
      mty.assertf(attr.kind == 'raw', 'kind: %s', attr.kind)
      if raw then
        p.l, p.c = l, c; p:error'multiple raw (##...) attributes'
      end
      local _, c1 = attr:lc1(p.root.decodeLC)
      local _, c2 = attr:lc2(p.root.decodeLC)
      raw = c2 - c1 + 1
    end
  end
  return raw
end

local function addToken(p, node, l1, c1, l2, c2)
  print('?? addToken', l1, c1, l2, c2)
  if l2 >= l1 and (l2>l1 or c2>=c1) then
    local t = Token:encode(p, l1, c1, l2, c2)
    print('?? added token:', p:tokenStr(t))
    mty.pnt('?? dat      :', p.dat)
    print('?? added sub  :', lines.sub(p.dat, l1, c1, l2, c2))
    add(node, t)
  else print("?? token=no")
  end
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
  mty.pnt'?? parsing list'
  p:skipEmpty()
  if p:isEof() then p:error'Expected a list got EOF' end
  local ipat, ikind; for ip, i in pairs(ITEM) do
    if p:consume(ip) then ipat, ikind = ip, i
      break
    end
  end
  if not ipat then p:error(LIST_ITEM_ERR) end
  mty.pntf('?? list ipat %q', ipat)
  local altEnd = function(p, node, l, c)
    local c1, c2 = p.line:find(ipat)
    mty.pntf('?? altEnd call %s.%s: %s => %s', p.l, p.c, p.line:sub(p.c), c1)
    return c2 and (p.c <= c2) and 'listStart' or false, l, c
  end
  while true do
    local item = {}
    mty.pntf('?? list item %s.%s: %s', p.l, p.c, p.line:sub(p.c))
    local r, l, c = M.content(p, item, false, altEnd)
    mty.pntf('?? list content returned: %s %s %s', r, l, c)
    if r == 'listStart' then
      addToken(p, item, l, c, p.l, p.c - 1)
      local c1, c2 = p.line:find(ipat, p.c)
      p.c = c2 + 1
    end
    add(list, item)
    if not r then break end
  end
end

-- skip whitespace, return whether it was skipped
local function skipWs(p)
  if not p.line then return end
  p.c = select(2, p.line:find('%S', p.c)) or #p.line + 1
end

-- increment line, adding token and skipping next line's whitespace.
-- include newline in token unless this line is EOF
local function incLine(p, node, l1, c1)
  local l2, c2 = p.l, #p.line
  if l1 ~= #p.dat then l2, c2 = l2 + 1, 0 end
  addToken(p, node, l1, c1, l2, c2)
  p:incLine(); skipWs(p)
  return p.l, p.c
end

M.content = function(p, node, isRoot, altEnd)
  local l, c = p.l, p.c
  ::loop::
  mty.pntf('?? l=%s: %s', l, p.line)
  if p.line == nil then
    mty.pnt('?? adding @EOF', l, c)
    assert(isRoot, "Expected ']' but reached end of file")
    return addToken(p, node, l, c, p.l - 1, #p.dat[p.l - 1])
  elseif #p.line == 0 then
    mty.pnt('?? Adding @br')
    add(node, {pos={l}, br=true})
    p:incLine(); skipWs(p)
    l, c = p.l, p.c
    goto loop
  elseif p.c > #p.line then
    mty.pnt('?? inc line')
    l, c = incLine(p, node, l, c)
    goto loop
  end
  if altEnd then
    local e = table.pack(altEnd(p, node, l, c))
    if e[1] then
      mty.pnt('?? content hit altEnd: ', e)
      return table.unpack(e)
    end
    print'?? not alt end'
  end
  local c1, c2 = p.line:find('[%[%]]', p.c); if not c2 then
    l, c = incLine(p, node, l, c)
    goto loop
  end
  p.c = c2 + 1
  mty.pnt('?? Adding @[]')
  addToken(p, node, l, c, p.l, c2-1)
  local posL, posC = p.l, p.c
  if p.line:sub(c1,c2) == ']' then
    if p.line:sub(c2+1, c2+1) == ']' then
      l, c = p.l, p.c; p.c = p.c + 1
      goto loop
    end
    return
  end
  local raw, ctrl = nil, p.line:sub(p.c, p.c)
  if ctrl == '' then
    p:error("expected control char after '['")
  elseif ctrl == RAW then
    local c1, c2 = p.line:find('^#+', p.c)
    assert(c2)
    p.c, raw = c2 + 1, c2 - c1 + 1
  end
  p.c = p.c + 1
  -- if p.c > #p.line then
  --   p:incLine(); skipWs(p)
  -- end
  local sub = {}
  if     raw           then sub.raw, sub.code       = raw, true
  elseif fmtAttr[ctrl] then sub[fmtAttr[ctrl]]      = true
  elseif strAttr[ctrl] then sub[strAttr[ctrl]], raw = true, 0
  elseif ctrl == '+'   then sub.list                = true
  elseif ctrl == '{'   then raw = parseAttrs(p, sub)
  elseif ctrl == '['   then l, c = p.l, p.c - 1; goto loop
  elseif ctrl == '<' then
    sub.href = assert(p:parse{PIN, Pat'[^>]*', '>'}[1])
  end
  if raw          then
    local s = bracketedStr(p, raw)
    sub.block = p:tokenStr(s):find'\n' and true or nil
    add(sub, s)
  elseif sub.list then parseList(p, sub)
  else                 M.content(p, sub) end
  sub.pos = {posL,posC,p.l,p.c-1}
  add(node, sub)
  l, c = p.l, p.c
  goto loop
end

M.parse = function(dat, dbg)
  local p = pegl.Parser:new(dat, pegl.RootSpec{dbg=dbg})
  skipWs(p)
  local node = {}
  M.content(p, node, true)
  return node, p
end

---------------------------
-- Testing Helpers

local SKIP_FOR_STR = ds.Set{'pos', 'raw'}
function M.parsedStrings(p, node)
  if type(node) ~= 'table' then return node end
  if mty.ty(node) == Token   then return p:tokenStr(node) end
  local n = {}
  for k, v in pairs(node) do
    if not SKIP_FOR_STR[k] then
      v = M.parsedStrings(p, v)
      n[k] = v
    end
  end
  return n
end

function M.assertParse(dat, expected, dbg)
  local node, p = M.parse(dat, dbg)
  civtest.assertEq(expected, M.parsedStrings(p, node))
end

M.fmtAttr = fmtAttr
M.htmlFmt  = ds.Set{'b', 'i', 'u'}

M.Writer = mty.doc[[
A Writer for cxt serializers (terminal, http, etc) to use.

The writer contains:
* The src lines and token decoder for getting pegl.Token values.
* The destination lines and current indent level.
]](mty.record'cxt.Writer')
  :field'src'
  :field'decodeLC'
  :field'to'
  :field('indent', 'number')
M.Writer.fromParser = function(ty_, p, to)
  return ty_{src=p.dat, decodeLC=p.root.decodeLC, to=to or {}, indent=0}
end
M.Writer.tokenStr = function(w, t) return t:decode(w.src, w.decodeLC) end
M.Writer.__index = function(w, l)
  local m = getmetatable(w)[l]; if m then return m end
  if type(l) ~= 'number' then return end
  mty.errorf('index cxt.Writer: %s', l)
end
M.Writer.__newindex = function(w, l, line)
  if type(l) ~= 'number' then return rawset(w, l, line) end
  if w.indent > 0 then line = string.rep(' ', w.indent)..line end
  w.to[l] = line
end
M.Writer.__len = function(w) return #w.to end

return M
