local G = G or _G

--- pegl: peg-like lua parser
local M = G.mod and G.mod'pegl' or {}

local mty     = require'metaty'
local fmt     = require'fmt'
local ds      = require'ds'
local lines   = require'lines'
local civtest = require'civtest'
local extend  = ds.extend
local push, pop = table.insert, table.remove
local sfmt    = string.format
local srep = string.rep
local pushfmt = ds.pushfmt
local ty = mty.ty

local function zero() return 0 end

--- Tokens use a packed span to preserve space.
--- Maximums: line start|len = 2^24|2^16. cols=255
M.SPAN_PACK = '>I3I2I2I2'
M.encodeSpan = function(l1, c1, l2, c2)
  return string.pack(M.SPAN_PACK, l1, c1, l2-l1, c2)
end
M.decodeSpan = function(s)
  local l, c, l2, c2 = string.unpack(M.SPAN_PACK, s)
  return l, c, l + l2, c2
end

M.Token = mty'Token'{'kind [string]: optional, used for debugging'}
M.Token.span = function(t, dec) return M.decodeSpan(t[1]) end
M.Token.encode=function(ty_, p, l, c, l2, c2, kind)
  return M.Token{M.encodeSpan(l, c, l2, c2), kind=kind}
end
M.Token.decode = function(t, dat) return lines.sub(dat, M.decodeSpan(t[1])) end
M.Token.__fmt = function(t, f)
  push(f, 'Tkn'); if t.kind then pushfmt(f, '<%s>', t.kind) end
  pushfmt(f, '(%s.%s %s.%s)', t:span())
end

local TOKEN_TY = {string=true, [M.Token]=true}
M.firstToken = function(list) --> t, listWithToken
  if TOKEN_TY[ty(list)] then return list, nil end
  local t = list[1]; while not TOKEN_TY[ty(t)] do
    list = t; t = list[1]
  end
  return t, list
end
M.lastToken = function(list) --> t, listWithToken
  if TOKEN_TY[ty(list)] then return list, nil end
  local t = list[#list]; while t and not TOKEN_TY[ty(t)] do
    list = t; t = list[#list]
  end
  return t, list
end

M.nodeSpan = function(t)
  local fst, lst = M.firstToken(t), M.lastToken(t)
  local l1, c1 = fst:span()
  return l1, c1, select(3, lst:span())
end

--- The root spec defines custom behavior for your spec. It's attributes
--- can be set to change how the parser skips empty (whitespace) and handles comments.
--- TODO: rename this.
M.RootSpec = mty'RootSpec' {
[==[skipEmpty [fn(p) -> nil]: default=skip whitespace [+
    * must be a function that accepts the `Parser`
      and advances it's `l` and `c` past any empty (white) space. It must also set
      `p.line` appropriately when `l` is moved.
    * The return value is ignored.
    * The default is to skip all whitespace (spaces, newlines, tabs, etc). This
      should work for _most_ languages but fails for languages like python.
    * Recommendation: If your language has only a few whitespace-aware nodes (i.e.
      strings) then hand-roll those as recursive-descent functions and leave
      this function alone.
  ]]==],

  'skipComment [function]: fn(p) -> Token for found comment',

[==[tokenizer [fn(p) -> nil] Requires: [+
    * must return one token. The default is to return a single punctuation character
      or a whole word ([$_%w])
    * Objects like [$Key] can use the single punctuation characters in a Trie-like
      performant data structure.
    ]]==],

  'dbg [boolean]',
}

--- The parser tracks the current position of parsing in `dat` and has several
--- convienience methods for hand-rolling your own recursive descent functions.
---
--- [" Note: the location is **line/col based** (not position based) because it
---    is designed to work with an application that stores the strings as lines
---    (a text editor) ]
M.Parser = mty'Parser'{
  'dat [lines]: reference to the underlying data.\n'
..'Must look like a table of lines',
  'l [int]: line, incremented when [$c] is exhausted',
  'c [int]: column in [$line]',
  'line [string]: the current line ([$dat[l]])',
  'lines',
  'root [RootSpec]',
  'stack [list]', 'stackL [list]', 'stackC [list]',
  'stackLast [{item, l, c}]',
  'commentLC [table]: table of {line={col=CommentToken}}',
  'dbgLevel [number]', dbgLevel = 0,
}

M.fmtSpec = function(s, f)
  if type(s) == 'string'   then return pushfmt(f, "%q", s) end
  if type(s) == 'function' then return push(f, fmt(s)) end
  if s.name or s.kind then
    push(f, '<'); push(f, s.name or s.kind); push(f, '>')
    return
  end
  if ty(s) ~= 'table' then push(f, mty.tyName(ty(s))) end

  f:level(1); push(f, f.tableStart)
  for i, sub in ipairs(s) do
    f(sub); if i < #s then push(f, ' ') end
  end
  f:level(-1); push(f, f.tableEnd)
end
M.specToStr = function(s, fmt)
  local fmt = fmt or fmt.Fmt:pretty()
  M.fmtSpec(s, fmt)
  return table.concat(fmt)
end

--- Create a parser spec record. These have the fields [$kind] and [$name]
--- and must define the [$parse] method.
M.specTy = function(name)
  return mty(name){'kind [string]', 'name [string]', __fmt=M.fmtSpec}
end

--- [$Pat{'%w+', kind='word'}] will create a Token with the span matching the
--- [$%w+] pattern and the kind of [$word] when matched.
M.Pat = M.specTy'Pat'
getmetatable(M.Pat).__call = function(T, t)
  if type(t) == 'string' then t = {t} end
  assert(#t > 0, 'must specify a pattern')
  return mty.construct(T, t)
end

local KEY_FORM =
  "construct Keys like Keys{{'kw1', 'kw2', kw3=true, kw4={sub-keys}, kind=...}"

local function constructKeys(keys)
  assert(ty(keys) == 'table', KEY_FORM)
  for i=1,#keys do
    keys[keys[i]] = true;
    keys[i] = nil end
  for k, v in pairs(keys) do
    if k == true then assert(v == true)
    else fmt.assertf(
      type(k) == 'string', 'number key after list items: %s', k)
    end
    if ty(v) == 'table' then keys[k] = constructKeys(v)
    elseif v ~= true then fmt.errorf('%s: %q', KEY_FORM, v) end
  end
  return keys
end

--- The table given to [$Key] forms a Trie which is extremely performant. Key depends
--- strongly on the [$tokenizer] passed to RootSpec.
---
--- Example: [$Key{{'myKeword', ['+']={'+'=true}}, kind='kw'}] will match tokens "myKeyword"
--- and "+" followed by "+" (but not "+" not followed by "+").
---
--- To also match "+" use [$['+']={true, '+'=true}]
---
--- ["Note: The `Key` constructor converts all list items into
---         [$value=true], so [${'a', 'b'}] is converted to [${a=true, b=true}]]
M.Key = mty'Key' {
  'keys [table]', 'name [string]', 'kind [string]',
  __fmt = M.fmtSpec,
}
getmetatable(M.Key).__call = function(T, t)
  local keys = assert(table.remove(t, 1), 'must provide keys at index 1')
  t['keys'] = constructKeys(keys)
  return mty.construct(T, t)
end

--- choose one spec
---
--- Example: [$Or{'keyword', OtherSpec, Empty}] will match one of the three
--- specs given.  Note that [$Empty] will always match (and return
--- [$pegl.EMPTY]).  Without [$Empty] this could return [$nil], causing a
--- parent [$Or] to match a different spec.
---
--- ["Note: [$Maybe(spec)] literally expands to [$Or{spec, Empty}]]
---
--- Prefer [$Key] if selecting among multiple string or token paths as [$Or] is
--- not performant ([$O(N)] vs Key's [$O(1)])
M.Or = M.specTy'Or'
M.Maybe = function(spec) return M.Or{spec, M.Empty} end
--- match a Spec multiple times
--- Example: [$Many{'keyword', OtherSpec, min=1, kind='myMany'}] will match the
--- given sequence one or more times ([$min=0] times by default). The parse
--- result is a list with [$kind='myMany'].
M.Many = mty'Many' {
  'min [int]', min = 0,
  'kind [string]', 'name [string]',
  __fmt = M.fmtSpec,
}

--- A Sequence of parsers. Note that [$Parser] treats [$Seq{'a'}] and [${'a'}]
--- identically (you can use plain tables instead).
---
--- Raw strings are treated as keywords (the are parsed literally and have
--- [$key] set to themselves). Functions are called with the [$parser] as the
--- only argument and must return the node/s they parsed or [$nil] for a
--- non-error match.
---
--- A sequence is a list of either other parsers
--- ([$Seq, {}, "keyword", fn(p), Not, Or, etc]} and/or plain strings which are
--- treated as keywords and will have [$kind] be set to themselves when parsed.
---
--- If the first spec matches but a later one doesn't an [$error] will be thrown
--- (instead of [$nil] returned) unless [$UNPIN] is used. See the PIN/UNPIN
--- docs for details.
---
--- [{h4}PIN/UNPIN: Syntax Error Reporting]
--- PEGL implements syntax error detection ONLY in Sequence specs (table specs i.e.
--- `{...}`) by throwing an [$error] if a "pinned" spec is missing. [+
---
--- * By default, no error will be raised if the first spec is missing. After the
---   first spec, [$pin=true] and any missing specs to throw an error with context.
---
--- * [$PIN] can be used to force [$pin=true] until [$UNPIN] is (optionally)
---   specified.
---
--- * [$UNPIN] can be used to force [$pin=false] until [$PIN] is (optionally)
---   specified.
---
--- * PIN / UNPIN only affect the [,current] sequence (they do not pin
---   sub-sequences).
--- ]
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
        p:dbg('COMMENT: %s.%s', p.l, p.c)
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
  else push(out, t) end
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
    if ty(t) ~= M.Token and #t == 1 then push(out, t[1])
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

--- Parse a spec, returning the nodes or throwing a syntax error.
---
--- [$root] is used to define settings of the parser such as how to skip
--- comments and whether to use debug mode.
M.parse = function(dat, spec, root) --> list[Node]
  local p = M.Parser:new(dat, root)
  return p:parse(spec), p
end

M.Parser.assertNode = function(p, expect, node, root)
  local result = p:toStrTokens(node)
  if not mty.eq(expect, result) then
    local eStr = table.concat(p.root.newFmt()(expect))
    local rStr = table.concat(p.root.newFmt()(result))
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
  return result
end

--- Parse the [$dat] with the [$spec], asserting the resulting "string tokens"
--- are identical to [$expect].
---
--- the input is a table of the form: [{# lang=lua}
---   {dat, spec, expect, dbg=nil, root=default} --> nil
--- ]#
M.assertParse = function (t) --> nil
  assert(t.dat, 'dat'); assert(t.spec, 'spec')
  local root = (t.root and ds.copy(t.root)) or M.RootSpec{}
  root.dbg   = t.dbg or root.dbg
  local node, parser = M.parse(t.dat, t.spec, root)
  if not t.expect and t.parseOnly then return end
  local result = parser:assertNode(t.expect, node)
  return result, node, parser
end

M.assertParseError=function(t)
  civtest.assertErrorPat(
    t.errPat,
    function() M.parse(assert(t.dat), assert(t.spec)) end,
    t.plain)
end

-------------------
-- Parser Methods

M.Parser.__tostring=function() return 'Parser()' end
M.Parser.new = function(T, dat, root)
  dat = (type(dat)=='string') and lines(dat) or dat
  return mty.construct(T, {
    dat=dat, l=1, c=1, line=dat[1], lines=#dat,
    root=root or M.RootSpec{},
    stack={}, stackL={}, stackC={}, stackLast={},
    commentLC={},
  })
end

--- the main entry point and used recursively.
--- Parses the spec, returning the node, which is a table of nodes that are
--- eventually tokens.
M.Parser.parse = function(p, spec) --> node
  local T = ty(spec)
  local specFn = SPEC_TY[T]
  if specFn then return specFn(p, spec)
  else           return spec:parse(p) end
end
--- consume the pattern, advancing the column if found
M.Parser.consume = function(p, pat, plain) --> Token
  local t = p:peek(pat, plain)
  if t then p.c = select(4, t:span()) + 1 end
  return t
end
--- identical to `consume` except it does not advance the column
M.Parser.peek = function(p, pat)
  if p:isEof() then return nil end
  local c, c2 = p.line:find(pat, p.c)
  if c == p.c then
    return M.Token:encode(p, p.l, c, p.l, c2)
  end
end
M.Parser.sub =function(p, t) -- t=token
  return lines.sub(p.dat, t:span())
end
M.Parser.incLine=function(p)
  p.l, p.c = p.l + 1, 1
  p.line = p.dat[p.l]
end
M.Parser.isEof=function(p) return not p.line end --> isAtEndOfFile
M.Parser.skipEmpty=function(p)
  p.root.skipEmpty(p)
  return p:isEof()
end
--- get the current parser state [${l, c, line}]
M.Parser.state   =function(p) return {l=p.l, c=p.c, line=p.line} end
--- restore the current parser state [${l, c, line}]
M.Parser.setState=function(p, st) p.l, p.c, p.line = st.l, st.c, st.line end
-- convert to token strings for test assertion
M.Parser.toStrTokens=function(p, n)
  if not n then return nil end
  if ty(n) == M.Token then
    local t = p:tokenStr(n)
    return n.kind and {t, kind=n.kind} or t
  elseif #n == 0 then return n end
  local t={} for _, n in ipairs(n) do push(t, p:toStrTokens(n)) end
  t.kind=n.kind
  return t
end
--- recursively mutate table converting all Tokens to strings
M.Parser.makeStrTokens = function(p, t) --> t
  for k, v in pairs(t) do
    if ty(v) == M.Token       then t[k] = p:tokenStr(v)
    elseif type(v) == 'table' then p:makeStrTokens(v) end
  end
  return t
end
M.Parser.tokenStr = function(p, t) return t:decode(p.dat) end --> string
-- recurse through the start of list and trim the start of first token
M.Parser.trimTokenStart = function(p, list)
  local t, list = M.firstToken(list); assert(list)
  if type(t) == 'string' then return end
  local l1, c1, l2, c2 = t:span()
  local line = p.dat[l1]
  local s = p:tokenStr(t); c1 = line:find('[^ ]', c1) or c1
  list[1] = M.Token:encode(p, l1, c1, l2, c2)
end

-- recurse through the end of list and trim the end of last token
M.Parser.trimTokenLast = function(p, list, trimNl)
  local t, list = M.lastToken(list); assert(list)
  if not t or type(t) == 'string' then return end
  local l1, c1, l2, c2 = t:span()
  local line = p.dat[l2]
  while line:sub(c2,c2) == ' ' do c2 = c2 - 1 end
  if trimNl and l2 > l1 and c2 == 0 then
    l2 = l2 - 1; c2 = #p.dat[l2]
  end
  list[#list] = M.Token:encode(p, l1, c1, l2, c2)
end

local function fmtStack(p)
  local b = {}; for i, v in ipairs(p.stack) do
    if v == true then -- skip
    else
      if type(v) ~= 'string' then v = fmt(v) end
      push(b, sfmt('%s(%s.%s)', v, p.stackL[i], p.stackC[i]))
    end
  end
  pushfmt(b, '%s(%s.%s)', table.unpack(p.stackLast))
  return table.concat(b, ' -> ')
end
M.Parser.checkPin=function(p, pin, expect)
  if not pin then return end
  if p.line then p:error(fmt.format(
    "parser expected: %q\nGot: %s",
    expect, p.line:sub(p.c))
  )else p:error(
    "parser reached EOF but expected: "..fmt(expect)
  )end
end
M.Parser.error=function(p, msg)
  local lmsg = sfmt('[LINE %s.%s]', p.l, p.c)
  fmt.errorf("ERROR\n%s%s\n%s\nCause: %s\nParse stack: %s",
    lmsg, p.line, srep(' ', #lmsg + p.c - 2)..'^',
    msg, fmtStack(p))
end
M.Parser.parseAssert=function(p, spec)
  local n = p:parse(spec); if not n then p:error(fmt.format(
    "parser expected: %q\nGot: %s",
    spec, p.line:sub(p.c))
  )end
  return n
end

M.Parser.dbgEnter=function(p, spec)
  push(p.stack, spec.kind or spec.name or true)
  push(p.stackL, p.l); push(p.stackC, p.c)
  if not p.root.dbg then return end
  p:dbg('ENTER: %s', fmt(spec))
  p.dbgLevel = p.dbgLevel + 1
end

M.Parser.dbgLeave=function(p, n)
  local sl = p.stackLast
  sl[1], sl[2], sl[3] = pop(p.stack), pop(p.stackL), pop(p.stackC)
  if not p.root.dbg then return n end
  p.dbgLevel = p.dbgLevel - 1
  p:dbg('LEAVE: %s(%s.%s)', fmt(n or sl[1]), sl[2], sl[3])
  return n
end
M.Parser.dbgMatched=function(p, spec)
  if p.root.dbg then p:dbg('MATCH: %s', fmt(spec)) end
end
M.Parser.dbgMissed=function(p, spec, note)
  if p.root.dbg then p:dbg('MISS: %s%s', fmt(spec), (note or '')) end
end
M.Parser.dbgUnpack=function(p, spec, t)
  if p.root.dbg then p:dbg('UNPACK: %s :: %s', fmt(spec), fmt(t)) end
end
M.Parser.dbg=function(p, fmtstr, ...)
  if not p.root.dbg then return end
  local msg = sfmt(fmtstr, ...)
  fmt.print(sfmt('%%%s%s (%s.%s)',
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

M.isKeyword = function(t) return #t == 1 and t.kind == t[1] end

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
  push(f, name..sfmt('{%s%s%s}',
    mty.eq(t[1],M.EMPTY) and '' or 'neg=1 ', t[2],
    (mty.eq(t[3],M.EMPTY) and '') or (','..t[4])
))end
M.fmtKinds = {
  EOF   = function(f, t) push(f, 'EOF')   end,
  EMPTY = function(f, t) push(f, 'EMPTY') end,
  name  = function(f, t) pushfmt(f, 'N%q', t[1]) end,
  n10   = function(...) fmtKindNum('NUM', ...) end,
  n16   = function(...) fmtKindNum('HEX', ...) end,
}
-- Override Fmt.table with an instance of this for copy/paste debugging
M.FmtPegl = mty'FmtPegl' {
  'kinds [table]: kind -> fmtFn', kinds=M.fmtKinds,
}
M.FmtPegl.__call = function(ft, f, t)
  if M.isKeyword(t) then pushfmt(f, 'KW%q', t[1]); return end
  local fmtK = t.kind and ft.kinds and ft.kinds[t.kind]
  if fmtK then fmtK(f, t) else fmt.Fmt.table(f, t) end
end
M.RootSpec.newFmt = function()
  local f = fmt.Fmt:pretty{}
  f.table = M.FmtPegl{}
  return f
end

return M
