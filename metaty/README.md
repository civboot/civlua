# metaty: simple but effective Lua type system using metatables

metaty is a minimalistic type library allowing users to express (runtime) types
in Lua and get the benefits of structured records like better formatting
(printing) and assertions.

It accomplishes this in less about 500 lines of Lua code. Since it only uses
metatables it can seamlessly interoperate with other Lua type solutions based on
metatables.

## Why?

Lua has a powerful metatable system which can be easily leveraged to make
rich types at minimal cost and high utility.

Lua is a fast and fun language. However it often lacks the ability to express
intent when it comes to the structure of data. It can also be difficult to
debug, since native tables only print something like `table: 0x1234` when
passed to `tostring`.

metaty provides:

* Type definitions (`record`, `rawTy`) with `:field` method.
* Easy equality checking (`eq`) and assertion (`assertEq`)
* Better formatting (`fmt`, `pnt` and `Fmt`) of values for debugging
* Getting the type of an object (`ty`, `tyName`)

## API

The API for metaty is very small but drastically improves the ergonomics of
developing for Lua.

#### record(name, metatable=nil)

Defines a Record with fields and methods.

This is similar to a struct or a class in other languages.

```
local record = require'metaty'.record

local A = record('A')
  :field('a2', 'number')
  :field('a1', 'string')
local B = record('B')
  :field('b1', 'number')
  :field('b2', 'number', 32)
  :field('a', A)

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

```
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

#### Runtime type checking

Runtime type checking has a cost and so is optional.

You can enable runtime type checking for ALL types by setting the global
`METATY_CHECK = true` before importing `metaty` at the top-level Lua module.

You can also enable it for yet-to-be-defined types by setting
`metaty.CHECK = true`.

You can override the constructor and/or `__index` functions to customize type
checking and other behavior.

