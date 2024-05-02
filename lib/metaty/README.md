# metaty: simple but effective Lua type system using metatables

**`./civlua.lua help metaty`**

Metatype is a library and specification for creating performant
documented and typo-safe Lua Types which can be formatted.

```
local M = mod and mod'myMod' or {} -- (see lib/pkg/README.md)
METATY_CHECK = true -- before require: turn on type check
local metaty = require'metaty'

-- Documentation for Pos (position)
M.Pos = metaty {
  'x[int]: x coordinate
  'y[int]: y coordinate
metaty
M.Pos.y = 0 -- default value

local p1 = Pos{x=4}
local p1 = Pos{x=4, y=3, z=5} -- error if checking turned on
```

The above expands to the following. Note that the "typosafe" elements
are removed when `METATY_CHECK == false`
```
local Pos = setmetatable({
  __name='Pos',

  -- used with metaty.Fmt and help()
  __fmt=metaty.recordFmt,
  __fields={'x', 'y', x='[int]', y='[int]'},
  __newindex = metaty.newindex, -- typosafe setting
}, {
  __call = function(T, t)
    metaty.fieldsCheck(T.__fields, t) -- typosafe constructor
    return setmetatable(t, T)
  end,
  __index = metaty.index, -- typosafe getting
})
Pos.__index = Pos
Pos.y = 0
DOC[Pos]       = 'Documentation for Pos (position)'
FIELD_DOC[Pos] = {x='x coordinate', y='y coordinate'}
```

## API

* `ty(v)` return the metaty of `v`. For tables this is `getmetatable(v)`,
  else it is `type(v)`.
* `record`'name' {'field1[type] documentation', 'field2[type]'}`
  creates a documented and typo-safe record type (see examples)
* `tostring(v)` convert `v` to string using `Fmt` (expands tables)
* `format(pat, ...)` the same as `string.format` except `%q` uses `Fmt` (expands
  tables).
* `eprint(...)` print to stderr (NOT stdout) using `Fmt` (expands tables)
* `eprintf(pat, ...)` shortcut for `eprint(format(pat, ...))`

## Why?

Lua is a fast and fun language. However it often lacks the ability to express
intent when it comes to the structure of data. Also, not only is it not
type-safe but it is also TYPO-unsafe -- small mistakes in the name of a field
can easily result in hard to diagnose bugs, even when they occur in one's
unit-test suite.

Checking for typos incurrs a small performance cost, so it is disabled by
default. However, it is well-worth the cost in your unit tests.

It is also WAY too difficult to format tables in Lua. This library and spec
provides a Formatter specification and implementation (`metaty.Fmt`).

## Specification
For a type to be considered a "metaty" the only requirement is that it has a
metatable set and that metatable has a `__name` field. Alternatively, it's
`__metatable` can be set to a string, in which case it emulates a "native" type.

The following fields can optionally be set on the metatable:

* `__fmt`: if present, will be called by a compliant Formatter object instead
  of formatting the object.
* `__fields`: should contain a table which contains fieldName -> fieldtype.
  fieldType can be an arbitrary string and is only for documentation, though
  future libraries/applications (type checkers) may eventually wish to consume
  it. `metaty` (the library) uses `[user-specified-type]`
  * This will be used by formatting libraries when printing the types
    (so the fields are printed in deterministic order).
* default values (i.e. `y` in the example) are assigned directly to the type.
  Documentation formatters may use these to format help messages.

In addition, there is runtime type specification defined below.

## Runtime typo checking (optional)

> Note: Runtime typo checking has a cost and so is **optional**
> (default=false).

To enable runtime checking set the global value `METATY_CHECK = true` at
the top of your application or test file (before executing ANY `require` calls).
**Set in TEST files only, or put behind a flag or env variable. Do not set it in
library/module/etc files**.

> Note: For your application you may want to add `assert(not metaty.getCheck())`
> after all your `require` calls to ensure typo checking was disabled.

You can override the typo-checking behavior with:

```
getmetatable(MyType).__call  = myConstructor
getmetatable(MyType).__index = myIndex
MyType.__newindex            = myNewIndex
```
