# metaty: simple but effective Lua type system using metatables

metaty is a minimalistic type library allowing users to express (runtime) types
in Lua and get the benefits of structured records like better formatting
(printing) and assertions.

It accomplishes this in a bit more than 500 lines of Lua code. Since it only
uses metatables it can seamlessly interoperate with other Lua type solutions
based on metatables.

## Why?

Lua has a powerful metatable type system which can be leveraged to make rich
runtime types.

Lua is a fast and fun language. However it often lacks the ability to express
intent when it comes to the structure of data. It can also be difficult to
debug, since native tables only print something like `table: 0x1234` when
passed to `tostring`.

metaty provides:

* Type definitions: `record`, `Fn`, `rawTy`
* Easy equality checking (`eq`) and assertion (`assertEq`)
* Better formatting for debugging: `fmt`, `pnt`, `Fmt`
* Getting the type of an arbitrary object: `ty`

## API

The API for metaty is very small but drastically improves the ergonomics of
developing for Lua.

#### record(name, metatable=nil)

Defines a Record with fields and methods.

This is similar to a struct or a class in other languages.

```lua
local mty = require'metaty'
local record, ty = mty.record, mty.ty

local A = record('A')
  :field('a2', 'number')
  :field('a1', 'string')
local B = record('B')
  :field('b1', 'number')
  :field('b2', 'number', 32) -- default=32
  :fieldMaybe('a', A) -- can be nil

-- Define methods
A.add = function(self, a)
    return A{a2=self.a2 + a.a2, a1=self.a1 + a.a1}
end

-- define your own constructor with a custom metatable
local C = record('C', {
  __new=function(ty_, t)
    t.field1 = 7
    return setmetatable(t, ty_) -- you have complete control
  end,
}
  :field('field1', 'number')
```

#### Fn{... inputs}:out{... outputs}:apply(function ...)

Specify (and optionally check) the types of a function.

```lua
local a2Add = Fn
         {A,     'number'} -- input types
:inpMaybe{false, true}     -- optional inputs (by index)
:out     {'number'}        -- output types
:apply(function(a, num)    -- register a function
  return a.a2 + (num or 0)
end)

assertEq({A, 'number'}, ty(a2Add).inputs) -- retrieve the type

local a = A{a1='hi', a2=4}
assertEq(A, ty(a))
assertEq(7, a2Add(a, 3)); assertEq(4, a2Add(a))

a2Add(a, 'four') -- throws invalid type error at argument 2
```

#### pnt(...)

`metaty.pnt(...)` is a much better print function. It not only prints values
using their `__fmt` method, it also prints tables in a clean and readable way.

#### assertEq(expect, result, pretty=true)

asserts two values are equal. If not then prints them out (formatted)
side-by-side and calls `error`.

#### fmt(value, set=nil) and Fmt{set=FmtSet{... settings}}

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

#### Runtime type checking (optional)

> Note: Runtime type checking has a cost and so is **optional**.
> The default is `metaty.CHECK = nil` (aka false).

You can enable runtime type checking for ALL types by setting the global
`METATY_CHECK = true` before any `require"metaty"` is executed (including by
sub-modules).

You can also enable it for yet-to-be-defined types by setting
`metaty.CHECK = true`.

> WARNING: neither of these should be done except for the **TOP LEVEL** module.
> They should NEVER be done in a library (except in the test files).

You can override the constructor and/or `__index` functions to customize type
checking and other behavior.

Type checking for records is setup in `forceCheckRecord`. You can override these
functions for individual records to alter how type checking behaves:

```
M.forceCheckRecord = function(r)
  r.__index    = M.indexChecked
  r.__newindex = M.newindexChecked
  r.__missing  = M.fieldMissing -- used by indexChecked
end
```

For functions you can get a checked and a non-checked version of the function
like so:

```
-- assuming CHECK=true
local function uncheckedFn() ... end
local checkedFn = Fn{}:apply(uncheckedFn)
assert(ty(uncheckedFn) == ty(checkedFn)) -- passes
```

