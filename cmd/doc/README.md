# doc: get documentation for Lua types at runtime

Get documentation on any Lua object. Includes documentation for several items
in the lua stdlibrary.

> Note: This requires the PKG protocol to be installed, see
> [lib/pkg](../pkg/README.md) and/or the guide below.

Usage (see also [Installation](#Installation]))
```
require'pkglib'() -- adds 'mod'
local doc = require'doc'
print(doc'ds.heap.Heap')
```

prints out:
```
## ds.heap.Heap (/home/rett/projects/civlua/lib/ds/ds/heap.lua:66) ty=Ty<Heap>
Heap(t, cmp) binary heap using a table.
A binary heap is a binary tree where the value of the parent always
satisfies `cmp(parent, child) == true`
  Min Heap: cmp = function(p, c) return p < c end (default)
  Max Heap: cmp = function(p, c) return p > c end

add and push take only O(log n), making it very useful for
priority queues and similar problems.

## Fields
  cmp             : [function]        

## Methods, Etc
  __fields        : table             
  __index         : Ty<Heap>          (ds/heap.lua:66)
  __name          : string            
  __newindex      : function          (metaty/metaty.lua:150)
  add             : function          (ds/heap.lua:75)
  pop             : function          (ds/heap.lua:85)
---- CODE ----
M.Heap = mty'Heap'{
  'cmp[function]: comparison function to use'
}
```

## Installation

This example shows how to install in your bash terminal to run
while in the `civ/` directory. Adapt it for other usecases:

```
LUA_PATH="./lib/pkg/?.lua"
LUA_PKGS="./"
alias luap="lua -e \"require'pkglib'()\""
function luahelp() {
  luap -e "require'civ'; print(require'doc'('$1'))"
}

# Now you can print docs for any type
luahelp ds.heap.Heap
luahelp string.format
luahelp for
```

## Library
Making a library's types self-documenting is easy:

```
-- My module docs
local M = mod and mod'myModName' or {}

-- my fn docs
M.myFn = function() ... end
```

See [lib/pkg](../pkg/README.md) for more details.

## Other Resources

* Lua API reference: https://www.lua.org/manual
* Tutorial style documentation: https://www.lua.org/pil/contents.html

Contributions welcome. All contributions (and this library) must be in the
public domain.
