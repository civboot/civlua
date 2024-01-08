# Civix: Lua linux and shell library

Civix is a thin wrapper around [luaposix] and provides [metaty] and [ds] types.

The core API is:
* `Pipe` for methods relating to reading/writing a pipe.
* `Pipes` for representing stdin/stdout/stderr (wrapped together).
* `sh` function for executing shell commands (can use `Pipes`)
* `shl` for executing lua-like shell commands (can use `Pipes`)
* `Fork` for running threads.

See [civix.lua](./civix.lua) for API documentation and [test.lua](./test.lua)
for example usage. For instance, Fork is a faithful (but more ergonomic)
representation of a direct unix (C) fork and I was personally surprised how easy
it is to use when the boilerplate of opening and naming pipes is better
encapsulated. Why use anything like the python `Thread` API when `fork` is
actually pretty simple?

```
assertEq('on stdout\n', sh[[ echo 'on' stdout ]].out)
assertEq(''           , sh[[ echo '<stderr from test>' 1>&2 ]].out)
assertEq('<stderr from test>',
  sh([[ echo '<stderr from test>' 1>&2 ]], {err=true}).err)
assertEq("foo --bool --bar='hi there'\n",
         sh{'echo', 'foo', bool=true, bar='hi there'})
```

[metaty]:   ../metaty/README.md
[ds]:       ../ds/README.md
[luaposix]: https://luarocks.org/modules/gvvaughan/luaposix
