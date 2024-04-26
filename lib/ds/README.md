# Lua ds: absurdly necessary data structures and algorithms

**`./civlua.lua help ds`**

`ds` is a small (<500 LoC) lua library which fills many of the data structure
and method gaps in Lua's standard library.

It contains the following functions and types. All types use
[metaty](../metaty/README.md) for specifying the type.

- comparable: `min`, `max`, `bound`, `isWithin`
- number: `isOdd`, `isEven`, `decAbs` (decrement absolute)
- string: `strDivide`, `strInsert`, `explode` (make table of characters),
  `concatToStrs`, (whitespace) `trimWs` and `split`, `matches` (gmatch table)
  `diffCol` (find column diff)
- lines submodule: `ds.lines(text)` to get table of lines, `span`, `sub(l, c,
  l2, c2)`, `diff` (first line:col)
- table (general): shallow `copy(t, update)`, `deepcopy(t)`, `emptyTable`
- table (list-like): `extend`, `reverse`, `indexOf`, `drain`
- table (map-like): `update`, `tryPath`, `get`, `getPath`, `setPath`, `getOrSet`
- Immutable types: `Imm{k=42}`, `imm(record'MyTy')`, `newSentinel`
- API: `none` `bool()` (see "none" section)
- source and debug: `callerSource`, `eval`
- file: `readPath(path)`, `writePath(path, text|lines)`

The following types are also defined:
- Duration and Epoch for time (must use civix/luaposix/etc to construct an
  Epoch)
- Hash Set: `Set{'zebra', 'anchovy'}:union{'corn', 'zebra'}`
- Linked List: `LL():addFront(1):addBack(2)`

## none: "set but none" vs nil's simply "unset"
In Lua `nil` always means "unset". Certain APIs (like JSON) might distinguish
between unset vs null/empty/none. For such APIs `none` can be used to mean "set
as none" instead of simply "unset" (which is what `nil` means).

`none` overrides `__metatable='none'` so that `getmetatable(none)=='none'` and
`metaty.ty(none) == 'none'`.

WARNING: `assert(none)` will pass.  Use `ds.bool` to make `none` falsy.

Note: calls `metaty.addNativeTy'none'`

## Imm and imm
`ds.Imm(myTable)` will make `myTable` immutable. In almost all ways it will
seem like a regular "table" type, even to `metaty.ty`. See the documentation for
caveats (a few minor ones). Any sub-tables will not be immutable.

You can make your own types immutable using `imm`, i.e.
`ds.imm(record'MyType):field'f1'`

Both are extremely fast during type-checking: each instance uses an inner table
with a single key/value and one indirection for lookups. They are zero-cost
(disabled) when `METATY_CHECK=falsy`.
