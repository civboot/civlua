# metaty: simple but effective Lua type system using metatables

**`./civlua.lua help metaty`**

Metatype is a library and specification which lets you create performant
typo-safe and documented Lua types.

```
METATY_CHECK = true -- before require: turn on type check
local mt = require'metaty'

local Pos = mt.doc[[
Documentation for Pos (position)
]](mt.record'Pos') {
  'x[int]: x coordinate
  'y[int]: y coordinate
}
Pos.y = 0 -- default value

local p1 = Pos{x=4}
local p1 = Pos{x=4, y=3, z=5} -- error if checking turned on
```

The above expands to roughly the following, features like
type checking and string formatting not included. See also:
[Specification](#Specification).

```
local Pos = setmetatable({
  __name='Pos',
  y = 0,
}, {
  __call = function(T, t) return setmetatable(t, T) end,
})
Pos.__index = Pos
DOC[Pos]       = 'Documentation for Pos (position)'
FIELD_DOC[Pos] = {x='x coordinate', y='y coordinate'}
```

## Why?

Lua is a fast and fun language. However it often lacks the ability to express
intent when it comes to the structure of data. Also, not only is it "type
unsafe" but it is also "typo unsafe" -- small mistakes in the name of a field
can easily result in hard to diagnose bugs.

It is also way too difficult to print tables (i.e. `table: 0x1234` by default).

## Specification
Any library can follow the type specification. For a type
to be considered a "metaty" it must only have a metatable
set to it with a `__name`. In addition, they can add documentation
for their types (including functions) by copy/pasting the following
global variables:

```
DOC       = DOC       or {} -- key=type/fn value=doc string
FIELD_DOC = FIELD_DOC or {} -- key=type    value=table of field docs
```

Their metatables can further more define the following fields:

* `__fields`: should contain a table which contains fieldName -> fieldtype.
  fieldType can be an arbitrary string and is only for documentation, though
  future libraries/applications (type checkers) may eventually wish to consume
  it. `metaty` (the library) uses `[user-specified-type]`
  * This will be used by formatting libraries when printing the types
    (so the fields are printed in deterministic order).
* default values (i.e. `y` in the example) are assigned directly to the type.
  Documentation formatters may use these to format help messages.

In addition, there is runtime type specification defined below.

## Runtime type checking (optional)

> Note: Runtime type checking has a cost and so is **optional**
> (default=false).

To enable runtime checking set the global value `METATY_CHECK = true` at
the top of your application or test file (before executing ANY `require` calls).
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
