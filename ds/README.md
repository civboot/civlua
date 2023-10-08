# Lua ds: absurdly necessary data structures and algorithms

`ds` is a small (<500 LoC) lua library which fills many of the data structure
and method gaps in Lua's standard library.

It contains the following functions and types. All types use
[metaty](../metaty/README.md) for specifying the type.

- none: `none` type, `bool` function
- comparable: `min`, `max`, `bound`, `isWithin`
- number: `isOdd`, `isEven`, `decAbs` (decrement absolute)
- string: `strDivide`, `strInsert`, `explode` (make table of characters),
  `concatToStrs`, (whitespace) `trimWs` and `splitWs`, `matches` (gmatch table)
  `diffCol` (find column diff)
- lines submodule: `span`, `sub(l, c, l2, c2)`, `split`, `diff` (first line:col)
- table (general): shallow `copy(t, update)`, `deepcopy(t)`, `emptyTable`
- table (list-like): `extend`, `reverse`, `indexOf`, `drain`
- table (map-like): `update`, `getPath`, `setPath`, `getOrSet`
- source and debug: `callerSource`, `eval`
- file: `readPath(path)`, `writePath(path, text|lines)`
- new types: `newSentinel` (create read-only sentinel values)

The following types are also defined:
- Duration and Epoch for time (must use civix or posix to construct an Epoch)
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
