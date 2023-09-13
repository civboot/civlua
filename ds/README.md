# Lua data structures

`ds` is a small (<500 LoC) lua library which fills many of the data structure
and method gaps in Lua's standard library.

It contains the following functions, all with [metaty](../metaty/README.md)
specified types:

- comparable: `min`, `max`, `bound`, `isWithin`
- number: `isOdd`, `isEven`, `decAbs` (decrement absolute)
- string: `strDivide`, `strInsert`, `explode` (make table of characters), `lines`
- table (general): shallow `copy(t, update)`, `deepcopy(t)`
- table (list-like): `extend`, `reverse`, `indexOf`
- table (map-like): `update`, `getPath`, `setPath`
- source code: `callerSource`, `eval`
- file: `readPath(path)`, `writePath(path, text|lines)`

The following types are also defined:
- Duration and Epoch
- Hash Set: `Set{'zebra', 'anchovy'}:union{'corn', 'zebra'}`
- Linked List: `LL():addFront(1):addBack(2)`
