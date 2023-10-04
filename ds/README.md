# Lua ds: absurdly necessary data structures and algorithms

`ds` is a small (<500 LoC) lua library which fills many of the data structure
and method gaps in Lua's standard library.

It contains the following functions and types. All types use
[metaty](../metaty/README.md) for specifying the type.

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

The following types are also defined:
- Duration and Epoch for time (must use civix or posix to construct an Epoch)
- Hash Set: `Set{'zebra', 'anchovy'}:union{'corn', 'zebra'}`
- Linked List: `LL():addFront(1):addBack(2)`
