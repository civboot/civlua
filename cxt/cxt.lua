
local mty = require'metaty'
local ds  = require'ds'
local add, sfmt = table.insert, string.format

local Key
local Pat, Or, Not, Many, Maybe
local Token, Empty, Eof, PIN, UNPIN
local EMPTY, common
local pegl = mty.lrequire'pegl'

local M = {}

-----------------------------
-- PEGL Definition (syntax)

local function extendEndPat(repr, pat, tk)
  local len = tk.c2 - tk.c1 + 1
  return repr..string.rep('-',  len),
         pat ..string.rep('%-', len)
end

local namePat = Pat'[_.-%w]+'
M.extend      = Pat{'%-+',      kind='extend'}
M.text        = Pat{'[^%[%]]+', kind='text'}

-- A string that ends in a closed bracket and handles balanced brackets.
-- Note: the token does NOT include the closing bracket.
M.bracketedStr = function(p)
  local l, c = p.l, p.c
  local nested = 1
  while nested > 0 do
    local c1, c2 = p.line:find('[%[%]]', p.c)
    if c2 then
      p.c = c2 + 1
      nested = nested + ((p.line:sub(c1, c2) == '[') and 1 or -1)
    else
      p:incLine()
      if p:isEof() then error(
        "Reached EOF but expected balanced string"
      )end
    end
  end
  p.c = p.c - 1 -- parser starts at closing bracket
  return Token:encode(p, l, c, p.l, p.c - 1)
end

M.attrSym = Key{kind='attrSym', {
  '!',             -- comment
  '*', '/', '_',   -- bold, italic, underline
  ':',             -- define node name
}}
M.keyval = {kind='keyval',
  namePat,
  Maybe{'=', '[^%s%[%]]+', kind='value'},
}
M.attr  = Or{ M.extend, M.attrSym, M.keyval, }
M.attrs =   {'{', Many{M.attr}, '}', kind='attrs'}

M.BLK = {
  ['*'] = '*',  ['/'] = '/',  ['_'] = '_', -- bold, italic, underline

  ['{'] = M.attrs,
  ['-'] = M.extend,
  ['<'] = {'<', Pat'[^>]*', '>', kind='url'},

  ['!'] = {'!',  M.bracketedStr, kind='comment'},
  ['#'] = {'#',  M.bracketedStr, kind='code'},
  ['.'] = {'%.', M.bracketedStr, kind='path'},
  ['@'] = {'@',  namePat,        kind='fetch'},
}
local VALID_BLK = {}
for k in pairs(M.BLK) do add(VALID_BLK, k) end
table.sort(VALID_BLK)
VALID_BLK = mty.fmt(VALID_BLK)

M.content = function(p)
  local l, c = p.l, p.c
  -- handle blank lines
  if c == 1 and p.line and #p.line == 0 then
    print('?? blank', l, c, p.l, p.c)
    local t = Token:encode(p, l, c, p.l, p.c - 1, 'blank')
    p:incLine()
    return t
  end
  local n = p:parse(M.text) if n then
    mty.pntset(mty.FmtSet{raw=true}, '?? text', n)
    return n
  end
  n = p:parse(M.blk); if n then
    mty.pnt('?? adding to blk', n)
    n.pos = {l, c, p.l, p.c - 1}
  end
  return n
end

M.blk = function(p)
  local start = p:consume'^%['; if not start then return end
  local blkTk = assert(p:peek'.', 'EOF after [')
  local blkCh = p:tokenStr(blkTk)
  local blkSpec = mty.assertf(M.BLK[blkCh],
    "ERROR %s.%s\nUnrecognized character after '[': %q, expected: %s",
    p.l, p.c, blkCh, VALID_BLK
  )
  local n = p:parseAssert(blkSpec)
  local endRepr, endPat = ']', '%]'
  if n.kind == 'extend' then
    endRepr, endPat = extendEndPat(endRepr, endPat, n)
  elseif n.kind == 'attrs' then for _, attr in ipairs(n) do
    if attr.kind == 'extend' then
      endRepr, endPat = extendEndPat(endRepr, endPat, attr)
      break
    end
  end end
  local out = {kind='blk', start, n}
  while true do
    mty.assertf(not p:isEof(), "expected closing %q", endRepr)
    n = p:consume(endPat); if n then add(out, n); return out end
    add(out, assert(p:parse(M.content)))
  end
end

-- Testing helpers
M.BLANK = {'', kind='blank'}
function M.T(text)           return {kind='text', text} end
M.fmtKind = ds.copy(pegl.RootSpec.fmtKind)
function M.fmtKind.blank(t, f) add(f, 'BLANK')           end
function M.fmtKind.text(t, f)  add(f, sfmt('T%q', t[1])) end

M.skipEmpty = function(p)
  -- advance line at EoL UNLESS it is blank line
  while not p:isEof() do
    if p.c > 1 and p.c > #p.line then p:incLine()
    else return end
  end
end

M.src = {Many{M.content}, Eof}
M.root = pegl.RootSpec{
  skipEmpty = M.skipEmpty,
  fmtKind = M.fmtKind,
}

-----------------------------
-- Record Definition
-- This checks and coverts the PEGL definition into records
-- which can then be converted into html/etc.

function M.toStrText(p, node)
  if type(node) ~= 'table' then return node end
  if node.text then
    local pos, n = node.pos, ds.copy(node)
    add(n, ds.lines.sub(p.dat, table.unpack(pos)))
    return n
  end
  local n = {}
  for k, v in pairs(node) do
    n[k] = M.toStrText(p, v)
  end
  return n
end

M.CxtRoot = mty.record'CxtTree'
  :field'root'
  :field'dat'
  :field'decodeLC'

M.CxtRoot.fromParser = function(ty_, p, root)
  local t = {
    root=root,
    dat=p.dat,
    decodeLC=p.root.decodeLC,
  }
  return mty.new(ty_, t)
end

M.CxtRoot.tokenStr = function(r, t--[[Token]])
  return t:decode(r.dat, r.decodeLC)
end

local symAttr = {
  ['*'] = 'b', ['/']='i', ['_']='u',
}
local directKinds = ds.Set{
  'comment', 'code', 'path', 'fetch', 'blank'
}

local tfmtAttr = ds.Set{'b', 'i', 'u'}
local function updateTextFmt(tfmt, attrs)
  if tfmtAttr:union(attrs) then
    tfmt = ds.copy(tfmt)
    for k, _ in pairs(tfmtAttr) do
      if attrs[k] then tfmt[k] = true end
    end
  end
  return tfmt
end

local function buildCxtNode(p, pNode, tfmt)
  if pNode.kind == 'blank' then
    return {blank=true, pos={table.unpack(pNode)}}
  end
  if mty.ty(pNode) == pegl.Token then
    local l, c = pNode:lc1(p.root.decodeLC)
    local node = {
      text=true, l=l, pos={l, c, pNode:lc2(p.root.decodeLC)}
    }
    ds.update(node, tfmt)
    return node
  end
  local node = {pos=assert(pNode.pos)}
  node.l = node.pos[1]
  local ctrl = pNode[2]
  if     symAttr[ctrl.kind]     then node[symAttr[ctrl.kind]] = true
  elseif directKinds[ctrl.kind] then node[ctrl.kind]          = true
  elseif ctrl.kind == 'attrs' then
    for _, attr in ipairs(ctrl) do
      if attr.kind == 'attrSym' then
        node[assert(symAttr[attr[1]])] = true
      elseif attr.kind == 'keyval' then
        local val = attr[2]
        if val == pegl.EMPTY then val = true
        else                      val = ds.only(val) end
        node[attr[1]] = val
      else
        assert(attr.kind == 'extend', attr.kind)
      end
    end
  elseif ctrl.kind == 'extend' then node.code = true
  elseif ctrl.kind == 'url'    then node.url  = ctrl[2]
  else error('Unknown kind: '..ctrl.kind) end
  tfmt = updateTextFmt(tfmt, node)
  local i = 3
  while i < #pNode do
    local cnode = buildCxtNode(p, pNode[i], tfmt)
    add(node, cnode)
    i = i + 1
  end
  if #node == 1 then
    for k, v in pairs(node) do
      if type(k) ~= 'number' then node[1][k] = v end
    end
    node = node[1]
  end
  return node
end

M.parse = function(dat, root)
  local parsed, p = pegl.parse(dat, M.src, root or M.root)
  mty.pnt('?? parsed: ', p:toStrTokens(parsed))

  local cxt, tfmt = {}, {}
  local l, line = 1, {}
  for _, pnode in ipairs(parsed) do
    mty.pnt('?? in : ', p:toStrTokens(pnode))
    mty.pnt('?? inraw : ', p:toStrTokens(pnode))
    mty.pntset(mty.FmtSet{raw=true}, '?? inraw: ', pnode)
    if pnode == pegl.EOF then break end
    local node = buildCxtNode(p, pnode, tfmt)
    mty.pnt('?? out: ', M.toStrText(p, node))
    mty.pntset(mty.FmtSet{raw=true}, '?? outraw: ', node)
    if node.pos[1] == l then add(line, node)
    else                add(cxt, line); line = {node} end
  end
  add(cxt, line)
  mty.ppnt('?? built cxt:', M.toStrText(p, cxt))
  return M.CxtRoot{
    root=cxt,
    dat=dat,
    decodeLC=p.root.decodeLC,
  }, p
end

----------------
-- HTML

return M
