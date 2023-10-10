# PEGL: PEG-like recursive descent Parser in Lua

> PEGL can now parse "real" Lua syntax (see `tests/test_lua.lua`), but is not
> yet in actual use anywhere.

PEGL is PEG like recursive descent Parser written in Lua.

Recursive descent is simultaniously one of the (conceptually) simplest parsers
while also being the one of the most powerful -- it's literally just function
recursion which walks a file stream. PEG is one of the simplest
parser-combinator languages, conceptually implementing a recursive descent
parser with a specific subset of features.

PEGL implements those features as a ultra-lightweight Lua library, maintaining
conciseness while avoiding any customized syntax.

## Resources
If you are completely new to parsers and especially if you want to write your
own language with an AST then I cannot recommend
[craftinginterpreters.com](http://www.craftinginterpreters.com) enough. It might
be a better place to start than this library.

## Introduction
A parser is a way to convert text into structured node objects so that the text
can be compiled or annotated by a program. For example you might want to convert
some source code like:

```
x = 1 + 2
```

Into something like:

```
{'x', '=', {'1', '+', '2', kind='op'}, kind='assign'}
```

A recursive descent parser does so via hand-rolled functions which typically
_recurse_ into eachother. Each function attempts to parse from the current
parser position using its spec (which may be composed of calling other parsing
functions) and returns either the successfully parsed node or `nil` (or returns
an error if it finds a syntax error).

PEGL is a Lua library for writing the common-cases of a recursive descent parser
in a (pure Lua) syntax similar to PEG, while still being able to easily fallback
to hand-rolled recursive descent when needed.

Most traditional PEG parsers struggle with complicated syntax such as Lua's
`[===[raw string syntax]===]`, python's whitespace denoted syntax or C's
lookahead requirements (`(U2)*c**h`) -- recursive descent can solve a lot of
these problems relatively easily and performantly.  However, recursive descent
parsers can be very verbose and sometimes difficult to understand. Below is a
comparison of the above example in both PEG, PEGL and a "traditional" (though
not very good) recursive descent implementation.

### Examples

PEG: most concise but harder to fallback to hand-rolled recursive descent
```
grammar = [[
num    <- '%d'
name   <- '%w'
setVar <- num '=' name
expr   <- setVar / ... other valid expressions
]]
p:parse(grammar)
```

PEGL: very concise and easy to fallback to hand-rolled recursive descent.
Things like `kind` and `name` make debug printing easier.
```
num    = Pat{'%d+', kind='num'} -- kind=num sets the node name
name   = Pat{'%w+', kind='name'}
-- Note: UNPIN and PIN are used for when errors should be raised
setVar = {UNPIN, name, '=', PIN, num, kind='setVar'}
expr   = Or{setVar, ... other valid expressions, name='expr'}
p:parse(expr)
```

Hand-rolled recursive descent: not very concise, harder to debug.
```
-- Note: p=parser, an object which tracks the current position
-- in it's `state`

function parseNum(p)
  local num = p:consume('%d+') -- return result and advance position
  if num then -- found
    return {num, kind='num'} end
  end
end

function parseSetVar(p)
  local state = p.state()
  local name = p:consume('%w+')
  if not name then return end
  local eq, num = p:consume('='), parseNum(p)
  if not (eq and num) then
    -- didn't match, reset state and return
    p.setState(state)
    return
  end
  return {{name, kind='name'}, eq, num, kind='setVar'}
end

function expression(p)
  local expr = parseSetVar(p)
  if expr then return expr end
  -- ... other possible expressions
end

expression(p)
```

## API

The basic API is to define a spec which is one or more Spec objects like
`Or{...}`, `{...}` (sequence), etc and then parse it with
`pegl.parse(text, spec)`.

### pegl.parse(text, spec, root)
Parse a spec, returning the nodes or throwing a syntax error.

`root` is used to define settings of the parser such as how to skip comments and
whether to use debug mode.

### pegl.assertTokens(dat, spec, expect)
Parse the `dat` with the `spec`, asserting the resulting "string tokens" are
identical to `expect`.

Useful for testing your grammar. See `tests/` for usage examples.

### Parser
The parser tracks the current position of parsing in `dat` and has several
convienience methods for hand-rolling your own recursive descent functions.

> Note: the location is **line/col based** (not position based) because it is
> designed to work with an application that stores the strings as lines (a text
> editor).

Fields:

* `dat`: reference to the underlying data. Must look like a table (`#dat` to get
  len, `dat[l]` to get line at `l`)
* `line`: the current line string. This is auto-set by `RootSpec.skipEmpty`
* `l`: the current line number. This is auto-incremented by `RootSpec.skipEmpty`
* `c`: the current column number (1-based index).
* `root`: the `RootSpec` for parsing.

Methods:

* `p:parse(spec)`: parse the (sub) spec, returning the result.
* `p:consume(pattern, plain)`: consume the pattern returning the `Token` on
   match and advancing the column
* `p:peek(pattern, plain)`: identical to `consume` except it does not advance
  the position.
* `p:isEof()`: return `true` if at the end of the file.
* `p:state()` and `p:setState(state)`: get/restore the current parser state.
  Useful if you need to backtrack (done automatically in `Or`).

### RootSpec
The root spec defines custom behavior for your spec and can be attached via
`pegl.parse(dat, {...}, RootSpec{...})`. It has the following fields:

`skipEmpty = function(p) ... end`

* must be a function that accepts the `Parser`
  and advances it's `l` and `c` past any empty (white) space. It must also set
  `p.line` appropriately when `l` is moved.
* The return value is ignored.
* The default is to skip all whitespace (spaces, newlines, tabs, etc). This
  should work for _most_ languages but fails for languages like python.
* Recommendation: If your language has only a few whitespace-aware nodes (i.e.
  strings) then hand-roll those as recursive-descent functions and leave
  this function alone.

`tokenizer = function(p)`
* must return one token. The default is to return a single punctuation character
  or a whole word (`_%w`)
* Objects like `Key` can use the single punctuation characters in a Trie-like
  performant data structure.

### Naitve Nodes: Token, EOF, EMPTY
A token represents an actual span of text and has fields `l, c, l2, c2`
which can be passed to `Parser:sub`.  A token can also have a `kind` value.

Other native nodes include:

* `Eof`: represents that the end of the file was reached: `{Many(expr), Eof}`
  will return `EOF` when the end of the file is reached
* `Empty`: always returns EMPTY: `Or{..., Empty}`
  will return `EMPTY` if none of the `...` items matched.

### Keyword: raw string
Any raw strings in the spec denotes a keyword. A "plain" match is performed and
if successful the returned node will have `kind` equal to the raw string.

### Pat: pattern
`Pat{'%w+', kind='word'}` will create a Token with the span matching the `%w+`
pattern and the kind of `word` when matched.

### Key: keyword trie
`Key{{'myKeword', ['+']={'+'=true}}, kind='kw'}` will match tokens `myKeyword`
and `+` followed by +` (but not `+` not followed by `+`).

To also match `+` use `['+']={true, '+'=true}}`.

The table given to `Key` forms a Trie which is extremely performant. Key depends
strongly on the `tokenizer` passed to `Root`.

> Implementation detail: The `Key` constructor converts all list items into
> `value=true`, so `{'a', 'b'}` is converted to `{a=true, b=true}`. Either
> `['+']=true}` or `['+']={[true]=true}` indicates that `+` is valid by itself.

### Or: choose one spec
`Or{'keyword', OtherSpec, Empty}` will match one of the three specs given.  Note
that `Empty` will always match (and return `EMPTY`). Without `Empty` this
could return `nil`, causing a parent `Or` to match a different spec.

> `Maybe(spec)` literally expands to `Or{spec, Empty}`

Prefer `Key` if selecting among multiple string or token paths as Or is not
performant (`O(N)` vs Key's `O(1)`)

### Seq: raw table of ordered Specs

`Seq{'keyword', OtherSpec, Or{'key', Empty}}` will match the exact order of
specs given. All raw tables are interpreted as `Seq`, so `{'a', 'b'}` is
equivalent to `Seq{'a', 'b'}`.

If the first spec matches but a later one doesn't an `error` will be thrown
(instead of `nil` returned) unless `UNPIN` is used. See the PIN/UNPIN docs for
details.

### Many: match a Spec multiple times
`Many{'keyword', OtherSpec, min=1, kind='myMany'}` will match the given sequence
one or more times (defult `min` is zero or more times). The result is a list of
`kind='myMany'` of sub-nodes with no kind.

### raw function: recursive descent
A Spec of a raw Lua function must have the arguments:

```
function rawFunction(p) -- p=Parser object
  -- perform recursive descent and return node/s
end
```

Return value:

* throw an error if it detects a syntax error
* return the Node/s if the spec matches
* return `nil` if the spec does not match (but is not immediately a syntax
  error)

## PIN/UNPIN: Syntax Error Reporting
PEGL implements syntax error detection ONLY in Sequence specs (table specs i.e.
`{...}`) by throwing an `error` if a "pinned" (see below) spec is missing.

* By default, no error will be raised if the first spec is missing. After the
  first spec, `pin=true` and any missing specs to throw an error with context.

* `PIN` can be used to force `pin=true` until `UNPIN` is (optionally)
  specified.

* `UNPIN` can be used to force `pin=false` until `PIN` is (optionally)
  specified.

* `PIN` / `UNPIN` only affect the _current_ sequence (they do not pin
  sub-sequences).

