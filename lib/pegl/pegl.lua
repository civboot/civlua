-- rd: recursive descent parser

local mty, ty = require'metaty'; ty = mty.ty
local ds      = require'ds'
local lines   = require'lines'
local civtest = require'civtest'
local extend  = ds.extend
local add, sfmt = table.insert, string.format

local M = {}
local function zero() return 0 end

-- Tokens use a packed span to preserve space.
-- Maximums: line start|len = 2^24|2^16. cols=255
M.SPAN_FMT = '>I3I2BB'
M.encodeSpan = function(l1, c1, l2, c2)
  return string.pack(M.SPAN_FMT, l1, c1, l2-l1, c2)
end
M.decodeSpan = function(s)
  local l, c, l2, c2 = string.unpack(M.SPAN_FMT, s)
  return l, c, l + l2, c2
end

M.Token = mty'Token'{'kind [string]: optional, used for debugging'}
M.Token.span = function(t, dec) return M.decodeSpan(t[1]) end
M.Token.encode=function(ty_, p, l, c, l2, c2, kind)
  return M.Token{M.encodeSpan(l, c, l2, c2), kind=kind}
end
M.Token.decode = function(t, dat) return lines.sub(dat, M.decodeSpan(t[1])) end

M.trimTokenStart = function(p, t)
  if mty.ty(t) ~= M.Token then return t end
  local l1, c1, l2, c2 = t:span()
  local line = p.dat[l1]
  local s = p:tokenStr(t); c1 = line:find('[^ ]', c1)
  return M.Token:encode(p, l1, c1, l2, c2)
end

M.trimTokenLast = function(p, t)
  if mty.ty(t) ~= M.Token then return t end
  local l1, c1, l2, c2 = t:span()
  local line = p.dat[l2]
  while line:sub(c2,c2) == ' ' do c2 = c2 - 1 end
  return M.Token:encode(p, l1, c1, l2, c2)
end

M.RootSpec = mty'RootSpec' {
  'skipEmpty [function]:   fn(p) default=skip whitespace',
  'skipComment [function]: fn(p) -> Token for found comment',
  'tokenizer [function]',
  'dbg [boolean]',
}

M.Parser = mty'Parser'{
  'dat',
  'l', 'c',
  'line', 'lines',
  'root [RootSpec]',
  'stack [table]',
  'stackLast',
  'commentLC [table]',
  'dbgLevel [number]', dbgLevel = 0,
}

M.fmtSpec = function(s, f)
  if type(s) == 'string' then
    return add(f, string.format("%q", s))
  end
  if type(s) == 'function' then
    return add(f, mty.tostring(s))
  end
  if s.name or s.kind then
    add(f, '<'); add(f, s.name or s.kind); add(f, '>')
    return
  end
  if mty.ty(s) ~= 'table' then add(f, mty.tyName(mty.ty(s))) end

  f:incIndent(); add(f, f.tableStart)
  for i, sub in ipairs(s) do
    f(sub); if i < #s then add(f, ' ') end
  end
  f:decIndent(); add(f, f.tableEnd)
end
M.specToStr = function(s, fmt)
  local fmt = fmt or mty.Fmt:pretty()
  M.fmtSpec(s, fmt)
  return table.concat(fmt)
end

local FIELDS = {
  {'kind', 'string'},
  {'name', 'string'}, -- for fmt only
}

M.specTy = function(name)
  return mty(name){'kind [string]', 'name [string]', __fmt=M.fmtSpec}
end

-- Pat'pat%wern' or Pat{'pat', kind='foo'}
M.Pat = M.specTy'Pat'
getmetatable(M.Pat).__call = function(T, t)
  if type(t) == 'string' then t = {t} end
  assert(#t > 0, 'must specify a pattern')
  return mty.construct(T, t)
end

local KEY_FORM =
  "construct Keys like Keys{{'kw1', 'kw2', kw3=true, kw4={sub-keys}, kind=...}"

local function constructKeys(keys)
  assert(mty.ty(keys) == 'table', KEY_FORM)
  for i=1,#keys do
    keys[keys[i]] = true;
    keys[i] = nil end
  for k, v in pairs(keys) do
    if k == true then assert(v == true)
    else mty.assertf(
      type(k) == 'string', 'number key after list items: %s', k)
    end
    if mty.ty(v) == 'table' then keys[k] = constructKeys(v)
    elseif v ~= true then mty.errorf('%s: %q', KEY_FORM, v) end
  end
  return keys
end

-- Key{{'myKeword', ['+']={'+'=true}}, kind='kw'}
M.Key = mty'Key' {
  'keys [table]', 'name [string]', 'kind [string]',
  __fmt = M.fmtSpec,
}
getmetatable(M.Key).__call = function(T, t)
  local keys = assert(table.remove(t, 1), 'must provide keys at index 1')
  t['keys'] = constructKeys(keys)
  return mty.construct(T, t)
end

M.Or = M.specTy'Or'
M.Maybe = function(spec) return M.Or{spec, M.Empty} end
M.Many = mty'Many' {
  'min [int]', min = 0,
  'kind [string]', 'name [string]',
  __fmt = M.fmtSpec,
}
M.Seq = M.specTy'Seq'
M.Not = M.specTy'Not'
M.Not.parse = function(self, p) return not M.parseSeq(p, self) end

-- Used in Seq to "pin" or "unpin" the parser, affecting when errors
-- are thrown.
M.PIN   = ds.sentinel('PIN',   {name='PIN',   kind=false})
M.UNPIN = ds.sentinel('UNPIN', {name='UNPIN', kind=false})

-- Denotes a missing node. When used in a spec simply returns Empty.
-- Example: Or{Integer, String, Empty}
M.EMPTY = ds.sentinel('EMPTY', {kind='EMPTY', __len=zero})
M.Empty = ds.sentinel('Empty', {parse = function() return M.EMPTY end})

-- Denotes the end of the file
M.EOF = ds.sentinel('EOF', {kind='EOF', __len=zero})
M.Eof = ds.sentinel('Eof', {
  __tostring=function() return 'Eof' end,
  parse=function(self, p)
    p:skipEmpty(); if p:isEof() then return M.EOF end
  end
})

-------------------
-- Root and Utilities

M.skipWs1 = function(p)
  if p.c > #p.line then p:incLine(); return
  else
    local c, c2 = p.line:find('^%s+', p.c)
    if c then p.c = c2 + 1; return end
  end
  return true
end

M.skipEmpty = function(p)
  local loop, sc, cmt, cL = true, p.root.skipComment
  while loop and not p:isEof() do
    loop = not M.skipWs1(p)
    if sc then
      cL = p.commentLC[p.l]; cmt = (cL and cL[p.c]) or sc(p)
      if cmt then -- cache for later and advance
        p:dbg('COMMENT: %s.%s', p.l, c)
        cL = p.commentLC[p.l]
        if not cL then cL = {}; p.commentLC[p.l] = cL end
        cL[p.c] = cmt
        p.l, p.c = select(3, cmt:span()); p.c = p.c + 1
      end
    end
  end
end
M.RootSpec.skipEmpty = M.skipEmpty

M.skipEmptyMinimal = function(p)
  while not p:isEof() do
    if p.c > #p.line then p:incLine()
    else return end
  end
end

M.defaultTokenizer = function(p)
  if p:isEof() then return end
  return p.line:match('^%p', p.c) or p.line:match('^[_%w]+', p.c)
end
M.RootSpec.tokenizer = M.defaultTokenizer

local UNPACK_SPECS = ds.Set{'table', M.Seq, M.Many, M.Or}
local function shouldUnpack(spec, t)
  local r = (
    type(t) == 'table'
    and UNPACK_SPECS[ty(spec)]
    and ty(t) ~= M.Token
    and not spec.kind
    and not t.kind
  )
  return r
end

-- Create node with optional kind
local function node(spec, t, kind)
  if type(t) ~= 'boolean' and t and kind then
    if type(t) == 'table' and not t.kind then t.kind = kind
    else t = {t, kind=kind} end
  end
  if shouldUnpack(spec, t) and #t==1 then t = t[1] end
  return t
end

-------------------
-- Key

M.Key.parse = function(key, p)
  p:skipEmpty()
  local c, keys, found = p.c, key.keys, false
  while true do
    local k = p.root.tokenizer(p); if not k    then break end
    keys = keys[k];                if not keys then break end
    p.c = p.c + #k
    if keys == true then found = true; break end
    found = keys[true]
  end
  if found then
    local kind = key.kind or lines.sub(p.dat, p.l, c, p.l, p.c - 1)
    return M.Token:encode(p, p.l, c, p.l, p.c -1, kind)
  end
  p.c = c
end

-------------------
-- Pat
M.Pat.parse = function(self, p)
  p:skipEmpty()
  for _, pat in ipairs(self) do
    local t = p:consume(pat)
    if t then
      t.kind = self.kind
      p:dbgMatched(t.kind or pat)
      return t
    end
  end
end

-------------------
-- Seq (table)
local function _seqAdd(p, out, spec, t)
  if type(t) == 'boolean' then -- skip
  elseif shouldUnpack(spec, t) then
    p:dbgUnpack(spec, t)
    extend(out, t)
  else add(out, t) end
end

M.parseSeq = function(p, seq)
  p:skipEmpty()
  local out, pin = {}, nil
  p:dbgEnter(seq)
  for i, spec in ipairs(seq) do
    if     spec == M.PIN   then pin = true;  goto continue
    elseif spec == M.UNPIN then pin = false; goto continue
    end
    local t = p:parse(spec)
    if not t then
      p:dbgMissed(spec)
      p:dbgLeave()
      return p:checkPin(pin, spec)
    end
    _seqAdd(p, out, spec, t)
    pin = (pin == nil) and true or pin
    ::continue::
  end
  local out = node(seq, out, seq.kind)
  p:dbgLeave(out)
  return out
end

M.Seq.parse = function(seq, p) return M.parseSeq(p, seq) end

-------------------
-- Or
M.Or.parse = function(or_, p)
  p:skipEmpty()
  p:dbgEnter(or_)
  local state = p:state()
  for _, spec in ipairs(or_) do
    local t = p:parse(spec)
    if t then
      t = node(spec, t, or_.kind)
      p:dbgLeave(t)
      return t
    end
    p:setState(state)
  end
  p:dbgLeave()
end

-------------------
-- Many
M.Many.parse = function(many, p)
  p:skipEmpty()
  local out = {}
  p:dbgEnter(many)
  while true do
    local t = M.parseSeq(p, many)
    if not t then break end
    if ty(t) ~= M.Token and #t == 1 then add(out, t[1])
    else _seqAdd(p, out, many, t) end
  end
  if #out < many.min then
    p:dbgMissed(many, ' got count=%s', #out)
    out = nil
  end
  p:dbgLeave(many)
  return node(many, out, many.kind)
end

-------------------
-- Misc
local SPEC_TY = {
  ['function']=function(p, fn) p:skipEmpty() return fn(p) end,
  string=function(p, kw)
    p:skipEmpty();
    local tk = p.root.tokenizer(p)
    if kw == tk then
      local c = p.c; p.c = c + #kw
      return M.Token:encode(p, p.l, c, p.l, p.c - 1, kw)
    end
  end,
  table=function(p, tbl) return M.parseSeq(p, tbl) end,
}

-- parse('hi + there', {Pat{'\w+'}, '+', Pat{'\w+'}})
-- Returns tokens: 'hi', {'+', kind='+'}, 'there'
M.parse = function(dat, spec, root)
  local p = M.Parser:new(dat, root)
  return p:parse(spec), p
end

M.assertParse=function(t) -- {dat, spec, expect, dbg=false, root=RootSpec{}}
  assert(t.dat, 'dat'); assert(t.spec, 'spec')
  local root = (t.root and ds.copy(t.root)) or M.RootSpec{}
  root.dbg   = t.dbg or root.dbg
  local node, parser = M.parse(t.dat, t.spec, root)
  local result = parser:toStrTokens(node)
  if not t.expect and t.parseOnly then return end
  if not mty.eq(t.expect, result) then
    local eStr = table.concat(root.newFmt()(t.expect))
    local rStr = table.concat(root.newFmt()(result))
    if eStr ~= rStr then
      print('\n#### EXPECT:'); print(eStr)
      print('\n#### RESULT:'); print(rStr)
      print()
      local b = {}; civtest.diffFmt(b, eStr, rStr)
      print(table.concat(b))
    else
      print('\n#### FORMATTED:'); print(eStr)
      print('## Note: They format the same but they differ')
      civtest.assertEq(t.expect, result)
    end
    assert(false, 'failed parse test')
  end
  return result, node, parser
end

M.assertParseError=function(t)
  civtest.assertErrorPat(
    t.errPat,
    function() M.parse(assert(t.dat), assert(t.spec)) end,
    t.plain)
end

M.Parser.__tostring=function() return 'Parser()' end
M.Parser.new = function(T, dat, root)
  dat = (type(dat)=='string') and lines(dat) or dat
  return mty.construct(T, {
    dat=dat, l=1, c=1, line=dat[1], lines=#dat,
    root=root or M.RootSpec{},
    stack={},
    commentLC={},
  })
end
M.Parser.parse = function(p, spec)
  local T = mty.ty(spec)
  local specFn = SPEC_TY[T]
  if specFn then return specFn(p, spec)
  else           return spec:parse(p)
  end
end
M.Parser.peek = function(p, pat)
  if p:isEof() then return nil end
  local c, c2 = p.line:find(pat, p.c)
  if c == p.c then
    return M.Token:encode(p, p.l, c, p.l, c2)
  end
end
M.Parser.consume = function(p, pat, plain)
  local t = p:peek(pat, plain)
  if t then p.c = select(4, t:span()) + 1 end
  return t
end
M.Parser.sub =function(p, t) -- t=token
  return lines.sub(p.dat, t:span())
end
M.Parser.incLine=function(p)
  p.l, p.c = p.l + 1, 1
  p.line = p.dat[p.l]
end
M.Parser.isEof=function(p) return not p.line end
M.Parser.skipEmpty=function(p)
  p.root.skipEmpty(p)
  return p:isEof()
end
M.Parser.state   =function(p) return {l=p.l, c=p.c, line=p.line} end
M.Parser.setState=function(p, st) p.l, p.c, p.line = st.l, st.c, st.line end
-- TODO: rename toStrNodes
M.Parser.toStrTokens=function(p, n)
  if not n then return nil end
  if ty(n) == M.Token then
    local t = p:tokenStr(n)
    return n.kind and {t, kind=n.kind} or t
  elseif #n == 0 then return n end
  local t={} for _, n in ipairs(n) do add(t, p:toStrTokens(n)) end
  t.kind=n.kind
  return t
end
-- (p, token) -> str
M.Parser.tokenStr = function(p, t)
  return t:decode(p.dat)
end

local function fmtStack(p)
  local stk = p.stack
  local b = {}; for _, v in ipairs(stk) do
    if v == true then -- skip
    elseif type(v) == 'string' then add(b, v)
    else add(b, mty.tostring(v)) end
  end
  add(b, sfmt('%s', p.stackLast))
  return table.concat(b, ' -> ')
end
M.Parser.checkPin=function(p, pin, expect)
  if not pin then return end
  if p.line then p:error(mty.format(
    "parser expected: %q\nGot: %s",
    expect, p.line:sub(p.c))
  )else p:error(
    "parser reached EOF but expected: "..mty.tostring(expect)
  )end
end
M.Parser.error=function(p, msg)
  mty.errorf("ERROR %s.%s\nstack: %s\n%s", p.l, p.c, fmtStack(p), msg)
end
M.Parser.parseAssert=function(p, spec)
  local n = p:parse(spec); if not n then p:error(mty.format(
    "parser expected: %q\nGot: %s",
    spec, p.line:sub(p.c))
  )end
  return n
end

M.Token.__fmt = function(t, f)
  add(f, 'Tkn')
  if t.kind then add(f, sfmt('<%s>', t.kind)) end
  add(f, sfmt('(%s.%s %s.%s)', t:span()))
end

M.isKeyword = function(t) return #t == 1 and t.kind == t[1] end

M.Parser.dbgEnter=function(p, spec)
  add(p.stack, spec.kind or spec.name or true)
  if not p.root.dbg then return end
  p:dbg('ENTER: %s', mty.tostring(spec))
  p.dbgLevel = p.dbgLevel + 1
end
M.Parser.dbgLeave=function(p, n)
  local sn = table.remove(p.stack); p.stackLast = sn
  if not p.root.dbg then return n end
  p.dbgLevel = p.dbgLevel - 1
  p:dbg('LEAVE: %s', mty.tostring(n or sn))
  return n
end
M.Parser.dbgMatched=function(p, spec)
  if not p.root.dbg then return end
  p:dbg('MATCH: %s', mty.tostring(spec))
end
M.Parser.dbgMissed=function(p, spec, note)
  if not p.root.dbg then return end
  p:dbg('MISS: %s%s', mty.tostring(spec), (note or ''))
end
M.Parser.dbgUnpack=function(p, spec, t)
  if not p.root.dbg then return end
  p:dbg('UNPACK: %s :: %s', mty.tostring(spec), mty.tostring(t))
end
M.Parser.dbg=function(p, fmt, ...)
  if not p.root.dbg then return end
  local msg = sfmt(fmt, ...)
  mty.print(string.format('%%%s%s (%s.%s)',
    string.rep('* ', p.dbgLevel), msg, p.l, p.c))
end

local _n10, _hpat = M.Pat'[0-9]+', '[a-fA-F0-9]+'
local n10 = {kind='n10', -- base 10 number
  M.UNPIN, M.Maybe'-',  _n10, M.Maybe{'.', _n10}
}
local n16 = {kind='n16', -- base 16 number
  M.UNPIN, M.Maybe'-',  M.Pat('0x'.._hpat),
  M.Maybe{'.', M.Pat(_hpat)},
}
local num = M.Or{name='num', n16, n10}
M.common = {num=num, n10=n10, n16=n16}

-- Debugging keywords(KW), names(N) and numbers(NUM/HEX)
M.testing = {}
local KW = function(kw)    return {kw, kind=kw} end -- keyword
local neg, dot = KW'-', KW'.'
local function NumT(kind, t)
  if type(t) == 'string' then t = {t} end; assert(#t <= 3)
  return ds.extend({kind=kind, (t.neg and neg) or M.EMPTY, tostring(t[1])},
    t[2] and {dot, tostring(t[2])} or {M.EMPTY})
end
M.testing.N = function(name) return {name, kind='name'} end -- name
M.testing.NUM = function(t)  return NumT('n10', t) end
M.testing.HEX = function(t)  return NumT('n16', t) end
M.testing.KW = KW

-- formatting parsed so it can be copy/pasted
local fmtKindNum = function(name, f, t)
  add(f, name..sfmt('{%s%s%s}',
    mty.eq(t[1],M.EMPTY) and '' or 'neg=1 ', t[2],
    (mty.eq(t[3],M.EMPTY) and '') or (','..t[4])
))end
M.fmtKinds = {
  EOF   = function(f, t) add(f, 'EOF')   end,
  EMPTY = function(f, t) add(f, 'EMPTY') end,
  name  = function(f, t) add(f, sfmt('N%q', t[1])) end,
  n10   = function(...) fmtKindNum('NUM', ...) end,
  n16   = function(...) fmtKindNum('HEX', ...) end,
}
-- Override Fmt.table with an instance of this for copy/paste debugging
M.FmtPegl = mty'FmtPegl' {
  'kinds [table]: kind -> fmtFn', kinds=M.fmtKinds,
}
M.FmtPegl.__call = function(ft, f, t)
  if M.isKeyword(t) then add(f, sfmt('KW%q', t[1])); return end
  local fmtK = t.kind and ft.kinds and ft.kinds[t.kind]
  if fmtK then fmtK(f, t) else mty.Fmt.table(f, t) end
end
M.RootSpec.newFmt = function()
  local f = mty.Fmt:pretty{}
  f.table = M.FmtPegl{}
  return f
end

M.firstToken = function(t)
  if mty.ty(t) == M.Token then return t end
  while true do
    for _, v in ipairs(t) do
      v = M.firstToken(v); if v then return v end
    end
  end
end

M.lastToken = function(t)
  if mty.ty(t) == M.Token then return t end
  while true do
    for _, v in ds.ireverse(t) do
      v = M.lastToken(v); if v then return v end
    end
  end
end

M.nodeSpan = function(t)
  local fst, lst = M.firstToken(t), M.lastToken(t)
  local l1, c1 = fst:span()
  return l1, c1, select(3, lst:span())
end

return M
