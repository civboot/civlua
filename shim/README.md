# shim: write scripts for Lua, execute from shell

`shim` is a tiny Lua module that converts a list of (shell) arguments into a Lua
table. It follows standard shell conventions.

Example:

```
mycmd a b c --foo=bar --baz --foo --name bob
```

Will be the following after shim.parse(args)
```
{'a', 'b', 'c', foo={bar, true}, baz=true, name='bob'}
```

In your script's `main.lua` you then call `shim{main=main}` and it will run your
script if and only if your script was called by bash (arg[0] == your script
name).

```
local function main(args)
  local t = shim.parse(args)
  ... your main function
end
shim {
  doc="my doc string",
  main=main,
}
```

Shim also provides a few convinience methods that one can use for duck-typing:

* `shim.num(v)`: if `v` is not a number returns `tonumber(v)`
* `shim.list(v)`: if `v` is not a table returns `{v}`
* `shim.auto(ty_, v)`: if `ty(v) == 'table'` then converts with `ty_(v)`
