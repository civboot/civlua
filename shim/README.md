# shim: write scripts for Lua, execute from shell

`shim` is a tiny Lua module that makes it easy to write command line utilities
in Lua without having to worry about it.  The main benefit (besides a wicked
simple argument parsing) is that your Lua function can be **either** called
directly in Lua or via a bash command, with very little overhead or complexity.

At its core shim:
1. Detects whether your Lua script was executed directly
2. Parses the list of (shell) arguments into a simple Lua table and passes it to
   the `exe` function you give it.

For example:
```
local shim = require'shim'
local M = {} -- normal module conventions

-- Implement file listing in lua.
-- You will probably want to write the result to `io.stdout` or
-- similar if `isExe=true`
M.ls = function(args, isExe) ...  end

-- Execute `exe` if this file was executed directly by bash.
-- Otherwise, this is a noop.
shim {
  help="list entries at a path ... and other docs",
  exe=M.ls,
}

return M
```

Then when the user calls your script you get the following:
```
lua ls.lua some/path  other/path  --time     --size=Mib
# args = {'some/path', 'other/path', time=true, size='MiB'}
```

You can use the other shim functions (`number`, `list`, etc) to help deal with
the dynamic duck typing problem of dealing with shell vs lua.

API:

* `shim{help=, exe=}` to auto-execute `exe` iff the script is called directly
  (i.e. `lua ls.lua`). If help is set and the user passes `--help` then the
  help message will be printed and the program will quit.
* `isExe(depth)` returns whether this script was called directly. Must call at
  the main level or set depth appropriately.
* `parse(args)` parse a list of string arguments to the shim table. Note that
  calling `shim` directly does this for you using the global `arg` value.

The following help with duck (dynamic) types, since your `exe` function won't
know whether it receives only string values (if called from shell) or proper lua
values (when called from lua).

* `boolean(val)`: convert val to a boolean.
  * `'true'  'yes' '1' true` return `true`
  * `'false' 'no'  '0' false nil` return `false`
* `number(num)`: if num is not a number then return `tonumber(num)`
* `list(val)`: if val is not a table then return `{val}`
* `listSplit(val, sep)`: split `val` into a list using `sep`. If `val` is
  already a list then split all the elements and flatten them.
* `new(ty, val)` if val does not have a `getmetatable` then return `ty(val)`
  * Note: strings DO have a metatable
  * This is primarily used with libraries like `metaty`

