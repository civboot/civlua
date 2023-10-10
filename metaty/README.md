# metaty: simple but effective Lua type system using metatables

**`./civlua.lua help metaty`**

metaty is a minimalistic type library allowing users to express (runtime) types
in Lua and get the benefits of structured records like better formatting
(printing) and assertions.

It accomplishes this in a bit more than 500 lines of Lua code. Since it only
uses metatables it can seamlessly interoperate with other Lua type solutions
based on metatables.

> For testing check out [civtest](../civtest/README.md) which has an `assertEq`
> built on `metaty.eq`

## Why?

Lua has a powerful metatable type system which can be leveraged to make rich
runtime types.

Lua is a fast and fun language. However it often lacks the ability to express
intent when it comes to the structure of data. It can also be difficult to
debug, since native tables only print something like `table: 0x1234` when
passed to `tostring`.

metaty provides:

* Getting the type of an arbitrary object: `ty`
* Type definitions: `record`, `rawTy`
* Easy equality checking (`eq`)
* Better formatting for debugging: `fmt`, `pnt`, `Fmt`
* More ergonomic imports: `lrequire`

## API

The API for metaty is very small but drastically improves the ergonomics of
developing for Lua.

### ty(val)
If `type(val) ~= "table"` this returns the result: `"nil", "boolean", "number",
"string"`

Else it returns `getmetatable(val) or "table"`

### record(name, metatable=nil)

Defines a Record with fields and methods.

```
local Point = record'Point'
  :field('x', 'number')
  :field('y', 'number')
  :fieldMaybe('z', 'number') -- can be nil

-- constructor
Point:new(function(ty_, x, y, z)
  return metaty.new(ty_, {x=x, y=y, z=z})
end
```

This is similar to a struct or a class in other languages. It is implemented as
a thin wrapper over a regular table using Lua's `setmetatable` where the
metatable is simply the record returned by `record'name'` (with whatever
`:field'name'`'s and `.method = function(self)...end` are set to it).

The record type (aka value metatable) has these fields set:
* `__name`: type name for formatting
* `__fields`: field types AND ordering by name (for formatting)
* `__index`: allows for method lookup from the record metatable. When type
  checking is enabled also checks `myRecord.field` types, etc.
* `__fmt`: function(self, fmt) used for formatting the type
* `__tostring`: by default calls `__fmt` to get the string.
* `metatable.__call`: the type's constructor, override with `:new(function)`

These are only used when type checking is enabled:
* `__maybes`: map of optional fields (allows `nil` values)
* `__newindex`: (optional) type checking for `myRecord[v]=field`
* `__missing`: (optional) function to call when a field is missing

> Note: Records have no concept of inheritance, but you could build inheritance
> through the `__check` method (used by `metaty.tyCheck`)

### pnt(...)

`metaty.pnt(...)` is a much better `print(...)` function.

* Uses `io.stdout` (`print` does NOT as of Lua 5.3)
* prints tables using their `__fmt` method and prints raw tables in a readable
  way.
* Use `ppnt(...)` for quick and easy pretty printing

```lua
pnt = require 'metaty'.pnt
pnt({1, 2, 3, foo='bar', baz='true'})
-- {1,2,3 :: foo=bar baz="true"}
ppnt{a=5, b=7}
-- {
--   a=5,
--   b=7,
-- }
```

### eq(a, b)

`metaty.eq` compares two values. If both are raw tables or are the same `ty` it
does a deep comparison of their keys/indexes.

### fmt(value, set=nil) and Fmt{set=FmtSet{... settings}}

All records have a default `__fmt` method defined which is used by `fmt`
function and `Fmt` object, etc.

> Note: by default a record's `__tostring` method is overriden to call the
> `__fmt(self, fmt)` method.

```lua
LuckyNumber = record('LuckyNumber')
  :field('description', Any, 'the lucky number is: ')
  :field('a', 'number')

-- add a custom format function (optional)
LuckyNumber.__fmt = function(self, fmt)
  -- Note: you can just call `table.insert(fmt, v)` to add items as well
  fmt:fmt(self.description) -- if description has __fmt it will call that.
  fmt:fmt(self.a)
  fmt:fmt(' ')
end

num = LuckyNumber{a=42}
pnt(num) -- "the lucky number is: 42\n"
```

### lrequire'module'
`lrequire` walks the local stack, setting nil slots to matching names from the
module.

```
-- Get a, b, and c from myModule into locals.
local a, b, c; metaty.lrequire'myModule'

-- vs
local mm = require'myModule'
local a, b, c = mm.a, mm.b, mm.c
```

`lrequire` also returns an index and takes an index as its second argument for
minor speed increase. This should be basically never necessary.

```
local d, e; local i = metaty.lrequire'other'
local f, g; metaty.lrequire('other', i)
```

## Runtime type checking (optional)

> Note: Runtime type checking has a cost and so is **optional**
> (default=false).

To enable runtime checking set the global value `METATY_CHECK = true` at
the top of your application or test file (before executing any `require` calls).
**Set in TEST files only, or main behind a developer flag. Do not set it in
library/module/etc files**.

> Note: For your application you may want to add `assert(not metaty.getCheck())`
> after all your `require` calls to ensure type checking was disabled.

Type checking for record types is setup in the constructor and
`forceCheckRecord`.  You can override these functions for individual record
types to alter how type checking behaves (regardless of `METATY_CHECK`):

```
myType.__index    = myIndex
myType.__newindex = myNewIndex
myType.__missing  = myMissing
ty(myType).__call = myConstructor
```
