-- rd: recursive descent parser

local mty, ty = require'metaty'; ty = mty.ty
local ds      = require'ds'
local civtest = require'civtest'
local extend, lines = ds.extend, ds.lines
local add, sfmt = table.insert, string.format

local M = {}

-- a 32bit float has 23 bits of fraction.
-- We use 8 for the column (0-255) and 15
-- for the line (0-32767).
M.encodeLCNum = function(l, c)
  assert((l <= 0x7FFF) and (c <= 0xFF), 'possible line/col overflow')
  return (l << 8) + c
end
M.decodeLCNum= function(lc)
  return lc >> 8, 0xFF & lc
end
M.encodeLCTbl = function(l, c) return {l, c} end
M.decodeLCTbl = table.unpack

M.Token = mty.record'Token'
  :fieldMaybe'kind'
M.Token.lc1=function(t, dec) return dec(t[1]) end
M.Token.lc2=function(t, dec) return dec(t[2]) end
M.Token.encode=function(ty_, p, l, c, l2, c2, kind)
  local e = p.root.encodeLC
  return M.Token{e(l, c), e(l2, c2), kind=kind}
end
M.Token.decode = function(t, dat, dec)
  local l, c = t:lc1(dec)
  return lines.sub(dat, l, c, t:lc2(dec))
end

M.RootSpec = mty.record'RootSpec'
  -- function(p): skip empty space
  -- default: skip whitespace
  :field('skipEmpty', 'function')
  -- skipComment: return Token for found comment.
  :fieldMaybe('skipComment', 'function')
  :field('tokenizer', 'function')
  :field('dbg', 'boolean', false)
  :field('fmtKind', 'table') -- default set at bottom
  :field('encodeLC', 'function', M.encodeLCNum)
  :field('decodeLC', 'function', M.decodeLCNum)

M.Parser = mty.record'Parser'
  :field'dat'
  :field'l' :field'c' :fieldMaybe'line' :field'lines'
  :field('root', M.RootSpec)
  :field('stack', 'table')
  :fieldMaybe'stackLast'
  :field('commentLC', 'table')
  :field('dbgLevel', 'number', 0)
  :fieldMaybe('fmtSet', mty.FmtSet)

M.fmtSpec = function(s, f)
  if type(s) == 'string' then
    return add(f, string.format("%q", s))
  end
  if type(s) == 'function' then
    return add(f, mty.fmt(s))
  end
  if s.name or s.kind then
    add(f, '<'); add(f, s.name or s.kind); add(f, '>')
    return
  end
  if mty.ty(s) ~= 'table' then add(f, mty.tyName(mty.ty(s))) end
  f:levelEnter('{')
  for i, sub in ipairs(s) do
    M.fmtSpec(sub, f);
    if i < #s then f:sep(' ') end
  end
  f:levelLeave('}')
end
M.specToStr = function(s, set)
  local set = set or mty.FmtSpec{}
  if set.pretty == nil then set.pretty = true end
  local f = mty.Fmt{set=set}; M.fmtSpec(s, f)
  return table.concat(f)
end

local function newSpec(name, fields)
  local r = mty.record(name)
  r.__index = mty.indexUnchecked
  r.__fmt = M.fmtSpec
  for _, args in ipairs(fields or {}) do
    local n, t = table.unpack(args)
    r:fieldMaybe(n, t)
  end
  return r
end

local FIELDS = {
  {'kind', 'string'},
  {'name', 'string'}, -- for fmt only
}
M.Pat = mty.doc[[Pat'pat%wern' or Pat{'pat', kind='foo'}]]
(ds.imm(newSpec('Pat'))
  :fieldMaybe'kind' :fieldMaybe'name')
M.Pat:new(function(ty_, t)
  if type(t) == 'string' then t = {t} end
  assert(#t > 0, 'must specify a pattern')
  return ds.newImm(ty_, t)
end)

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
    else mty.assertf(v == true, '%s: %s', KEY_FORM, mty.fmt(v)) end
  end
  return keys
end

M.Key = newSpec'Key' -- Key{{'myKeword', ['+']={'+'=true}}, kind='kw'}
  :field'keys' :fieldMaybe'name' :fieldMaybe'kind'
M.Key:new(function(ty_, k)
  local keys = assert(table.remove(k, 1), 'must provide keys at index 1')
  k['keys'] = constructKeys(keys)
  return mty.newUnchecked(ty_, k)
end)

M.Or = newSpec('Or', FIELDS)
M.Maybe = function(spec) return M.Or{spec, M.Empty} end
M.Many = newSpec'Many'
  :fieldMaybe('kind', 'string')
  :field('min', 'number', 0)
  :fieldMaybe('name', 'string')
M.Seq = newSpec('Seq', FIELDS)
M.Not = newSpec('Not', FIELDS)

-- Used in Seq to "pin" or "unpin" the parser, affecting when errors
-- are thrown.
M.PIN   = ds.newSentinel('PIN',   {name='PIN'})
M.UNPIN = ds.newSentinel('UNPIN', {name='UNPIN'})

-- Denotes a missing node. When used in a spec simply returns Empty.
-- Example: Or{Integer, String, Empty}
M.Empty = mty.record'Empty'
M.EMPTY = ds.Imm{kind='EMPTY'}

-- Denotes the end of the file
M.Eof = mty.record('Eof', {__tostring=function() return 'EOF' end})
M.EOF = ds.Imm{kind='EOF'}

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

-- Default skipEmpty function.
M.RootSpec.skipEmpty = function(p)
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
        p.l, p.c = cmt:lc2(p.root.decodeLC); p.c = p.c + 1
      end
    end
  end
end

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

local function parseSeq(p, seq)
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

M.Seq.parse = function(seq, p) return parseSeq(p, seq) end

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
    local t = parseSeq(p, many)
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
M.Not.parse = function(self, p) return not parseSeq(p, self) end
M.Eof.parse = function(self, p)
  p:skipEmpty(); if p:isEof() then return M.EOF end
end
M.Empty.parse = function() return M.EMPTY end

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
  table=function(p, tbl) return parseSeq(p, tbl) end,
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
  if t.expect ~= result then
    local eStr = parser:fmtParsedStrs(t.expect)
    local rStr = parser:fmtParsedStrs(result)
    if eStr ~= rStr then
      print('\n#### EXPECT:'); print(eStr)
      print('\n#### RESULT:'); print(rStr)
      print()
      local b = {}; civtest.diffFmt(b, eStr, rStr)
      print(table.concat(b))
      assert(false, 'failed parse test')
    end
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
M.Parser.new = function(ty_, dat, root)
  dat = (type(dat)=='string') and ds.lines(dat) or dat
  return mty.new(ty_, {
    dat=dat, l=1, c=1, line=dat[1], lines=#dat,
    root=root or M.RootSpec{},
    stack={},
    commentLC={},
  })
end
M.Parser.parse = function(p, spec)
  local ty_ = mty.ty(spec)
  local specFn = SPEC_TY[ty_]
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
  if t then p.c = select(2, t:lc2(p.root.decodeLC)) + 1 end
  return t
end
M.Parser.sub =function(p, t) -- t=token
  local l, c = t:lc1(p.root.decodeLC)
  return lines.sub(p.dat, l, c, t:lc2(p.root.decodeLC))
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
M.Parser.toStrTokens=function(p, n--[[node]])
  if not n then return nil end
  if ty(n) == M.Token then
    local t = p:tokenStr(n)
    return n.kind and {t, kind=n.kind} or t
  elseif #n == 0 then return n end
  local t={} for _, n in ipairs(n) do add(t, p:toStrTokens(n)) end
  t.kind=n.kind
  return t
end
M.Parser.tokenStr = function(p, t--[[Token]])
  return t:decode(p.dat, p.root.decodeLC)
end
M.Parser.fmtSetDefault = function(p) return mty.FmtSet{
  data=p, pretty=true, listSep=', ', tblSep=', ',
}end
M.Parser.fmtParsedStrs=function(p, nodeStrs)
  p.fmtSet = p.fmtSet or p:fmtSetDefault()
  p.fmtSet.tblFmt = M.tblFmtParsedStrs
  return mty.fmt(nodeStrs, p.fmtSet)
end
M.Parser.fmtParsedTokens=function(p, nodeTokens)
  p.fmtSet = p.fmtSet or p:fmtSetDefault()
  p.fmtSet.tblFmt = M.tblFmtParsedTokens
  return mty.fmt(nodeTokens, p.fmtSet)
end

local function fmtStack(p)
  local stk = p.stack
  local b = {}; for _, v in ipairs(stk) do
    if v == true then -- skip
    elseif type(v) == 'string' then add(b, v)
    else add(b, mty.fmt(v)) end
  end
  add(b, sfmt('%s', p.stackLast))
  return table.concat(b, ' -> ')
end
M.Parser.checkPin=function(p, pin, expect)
  if not pin then return end
  if p.line then p:error(sfmt(
    "parser expected: %s\nGot: %s",
    mty.fmt(expect), p.line:sub(p.c))
  )else p:error(sfmt(
    "parser reached EOF but expected: %s", ty.fmt(expect)
  ))end
end
M.Parser.error=function(p, msg)
  mty.errorf("ERROR %s.%s\nstack: %s\n%s", p.l, p.c, fmtStack(p), msg)
end
M.Parser.parseAssert=function(p, spec)
  local n = p:parse(spec); if not n then p:error(sfmt(
    "parser expected: %s\nGot: %s",
    mty.fmt(spec), p.line:sub(p.c))
  )end
  return n
end

M.Token.__fmt = function(t, f)
  local p = f.set.data
  if ty(f.set.data) == M.Parser then
    M.tblFmtParsedTokens(t, f)
  elseif t.kind then add(f, sfmt('<%s>', t.kind))
  else add(f, 'Tkn'); mty.tblFmt(t, f) end
end

function M.isKeyword(t) return #t == 1 and t.kind == t[1] end
M.tblFmtParsedStrs = function(t, f)
  if M.isKeyword(t) then add(f, sfmt('KW%q', t[1])); return end
  local fmtK = f.set.data and f.set.data.root.fmtKind
  local fmtK = t.kind and fmtK and fmtK[t.kind]
  if fmtK then fmtK(t, f)
  elseif type(t) == 'table' then mty.tblFmt(t, f)
  else error('not a table: '..mty.fmt(t)) end
end
M.tblFmtParsedTokens = function(t, f)
  local p = f.set.data
  local fmtK = t.kind and p.root.fmtKind[t.kind]
  local st = ((ty(t)==M.Token) or fmtK) and p:toStrTokens(t)
  if st then -- ya this is hacky. Don't execute from multiple threads
    if type(st) == 'string' then add(f, sfmt('%q', st)); return end
    f.set.tblFmt = M.tblFmtParsedStrs;
    f.set.tblFmt(st, f)
    f.set.tblFmt = M.tblFmtParsedTokens
  elseif type(t) == 'table' then mty.tblFmt(t, f)
  else error(mty.fmt(t)) end
end

M.Parser.dbgEnter=function(p, spec)
  add(p.stack, spec.kind or spec.name or true)
  if not p.root.dbg then return end
  p:dbg('ENTER: %s', mty.fmt(spec))
  p.dbgLevel = p.dbgLevel + 1
end
M.Parser.dbgLeave=function(p, n)
  local sn = table.remove(p.stack); p.stackLast = sn
  if not p.root.dbg then return n end
  p.dbgLevel = p.dbgLevel - 1
  p:dbg('LEAVE: %s', mty.fmt(n or sn))
  return n
end
M.Parser.dbgMatched=function(p, spec)
  if not p.root.dbg then return end
  p:dbg('MATCH: %s', mty.fmt(spec))
end
M.Parser.dbgMissed=function(p, spec, note)
  if not p.root.dbg then return end
  p:dbg('MISS: %s%s', mty.fmt(spec), (note or ''))
end
M.Parser.dbgUnpack=function(p, spec, t)
  if not p.root.dbg then return end
  p:dbg('UNPACK: %s :: %s', mty.fmt(spec), mty.fmt(t))
end
M.Parser.dbg=function(p, fmt, ...)
  if not p.root.dbg then return end
  local msg = sfmt(fmt, ...)
  mty.pnt(string.format('%%%s%s (%s.%s)',
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
local function NumT(kind, t)
  if type(t) == 'string' then t = {t} end; assert(#t <= 3)
  return ds.extend({kind=kind, (t.neg and '-') or M.EMPTY, t[1]},
    t[2] and {'.', t[2]} or {M.EMPTY})
end
local KW = function(kw)    return {kw, kind=kw} end -- keyword
function M.testing.N(name) return {name, kind='name'} end -- name
function M.testing.NUM(t)  return NumT('n10', t) end
function M.testing.HEX(t)  return NumT('n16', t) end
M.testing.KW = KW

-- formatting parsed so it can be copy/pasted
local fmtKindNum = function(name, t, f)
  add(f, name..sfmt('{%s%s%s}',
    mty.eq(t[1],M.EMPTY) and '' or 'neg=1 ', t[2],
    (mty.eq(t[3],M.EMPTY) and '') or (','..t[4])
))end
M.RootSpec.fmtKind = {
  EOF   = function(t, f) add(f, 'EOF')   end,
  EMPTY = function(t, f) add(f, 'EMPTY') end,
  name  = function(t, f) add(f, sfmt('N%q', t[1])) end,
  n10   = function(t, f) fmtKindNum('NUM', t, f) end,
  n16   = function(t, f) fmtKindNum('HEX', t, f) end,
}

return M
