# Zoa: low level type definition and serialization

Zoa is a serialization and type framework inspired by protobuf and capnproto.
It's primary goals are:

* Specify types that are valid across language paradigms (especially C and Lua)
* Be able to serialize/deserialize types specified by Zoa to/from any language
* Simplicity and minimalism

Zoa is part of the [Civboot] project which aims to create a simple yet useable
and understandable software stack.

> zoa is named after "protozoa", a nod to protobufs.

## Zoa Types (.zty)

Zoa types are specified in a `.zty` file in the syntax below. They have a
defined seralization format (defined in **Serialization**) and have minimalistic
support for constants (**Constants**).

Zoa supports the following native types, which mimick Lua's [packfmt][packfmt]

```
  b: a signed byte (char)
  B: an unsigned byte (char)
  i[n]: a signed int with n=2,4,8 bytes
  I[n]: a unsigned int with n=2,4,8 bytes
  n[n]: a number(float) with n=4,8 bytes (IEEE single,double)
  s[n]: a counted string with n=1,2,4 byte count.
```

* types from packfmt not listed, such as "native length" types, are not
  supported
* For Lua, `require'zoa'` adds the above types as metaty native types. This
  means they typecheck with "number", "string", etc. Other languages should
  behave in a similar fashion (i.e. C alias or `#define`)

zty syntax also accommodates the following complex types:

* `&[t]` for a reference to type `[t]`
  * Multiple references (`&&type`) are NOT supported, but can be achieved by
    wrapping in a struct: `struct r_i4[r:&i4]` then  `&r_i4`
* `Arr[type]` is an array encoded as a length and a reference.
* user-defined types:
  * struct: C struct / Product type
  * enum: C tagged union / Sum type
* `s` must always be behind a reference (it has a non-static size)

```
struct Point [x:i4, y:i4]
enum TagKind [
  notag,    -- no data
  id:I4,    -- data=I4 integer
  name:&s1, -- data=reference to counted string
]
struct Tag   [kind:TagKind, point:&Point]
struct Data [
  points: Arr[Point], -- array of points
  tags:   Arr[Tag],   -- array of tags
]
```

Zoa also comes pre-defined with a few standard types. If your language already
has these types, then your `zoa` library should implement a serializer interface
(or similar) for them. Below is their structure when serialized:

```
enum ZTy; struct ZPair; -- declared, defined below
struct Duration   [ I8 sec , U4 ns                 ]
struct Time       [ I8 sec , U4 ns                 ] -- unix Epoch
struct DateTime   [ I4 year, U2 day, U4 sec, U4 ns ]
struct Date       [ I8 year, U2 day,               ]
struct Year       [ I8 year ]
struct List       [ Arr[ZTy]                       ]
struct Map        [ Arr[ZPair]                     ]

struct ZPair      [ key: ZTy  value: ZTy           ]
enum   ZTy        [
  t_b:b  t_B:B  t_i1:i1  t_i2:i2, ... native types
  duration:Duration  time:Time,   ... pre-defined types (except ZPair)
]
```

> Note: `sizeof(ZTy) == wordsize + 8`

## Serialization
> This section details how serialization is implemented in Lua. For other
> languages it will be very similar.

The simplest version of serialization is
of a type with no references or arrays:

* Recursively unwrap the record's fields+subfields (all of which reduce to
  native types) into a flat table.
* Call `string.pack` on the concatenation of the native types.
  * Optional C compatibility can be achieved by adding appropriate `x` padding
    for alignment (when needed) for sub-structs.

Simple deserialization is the reverse: unpack the string and then walk and set
the fields from the resulting array.

The existence of references and/or arrays complicates things: multiple
references can refer to the same object and that is valuable compression. Also,
infinite recursion would be possible if we attempt to recursively copy through
references.

To handle references, every referred value must be given an index (we call it an
`idx`), and when serialized all references will instead use the `idx`. For
serializing, we must also prefix every value with the type (so that we can know
its size) and if it's an array we must know its length as well. To accomplish
this there will be a HEADER that contains all the type specs, each of which will
have an `ity` (type id). See HEADER for that structure.

The basic serialization is:

* walk all values recursively. Every value behind a reference is put in a
  `table[value] = nextIdx()` where the idx is a number that increments from `1`
  (`0` is reserved as `null`). If the value is already in the table it is skipped.
  * Every field _within_ a value (for a struct or enum) gets its own idx (but is
    not prefixed by a tid since that is already known).  Enum's always consume
    the maximum number of idxs any of their variants would consume.
  * For arrays, the whole array uses the first idx, and each value gets its own
    set of idxs (again not prefixed by tid). This allows fields to reference
    either the whole array OR values within the array.
  * s (strings) cannot have references to their internal values (they are given
    exactly one idx)
* From now on, any references will use the idx to refer to the value.
* The values in this table are then serialized from idx high->low. Each value is
  prefixed by its ity (the types must be a known constant size) and if it's an
  Array it's encoded length.
* The remaining root values are serialized using `ity=0`, which is reserved

Deserialization is the reverse:
* Items are deserialized into a table keyed by idx
* Any references use the idx to lookup the value to determine the actual reference.
* The result is the final root values (`ity=0`)

### HEADER of itys (type ids)

The HEADER is structured as a series of `ity:packfmt\n` to define the type and
`ity=name field1name field2name\n` to define the name. `ity` is an integer
encoded as [base64url], `packfmt` is the same as that defined in the **Zoa Types**
section with the following additions:

* `{ity}` a base64 ity, i.e. a field with user-defined type
* `A[t]` an array of type `[t]
* `&[t]` a reference of type `[t]`

The following must be the first character after `:`
* `S` struct, the spec is the fields in-order.
* `E` enum, the spec is the variants in-order.

Examples:
```
  ad:SAi4                -- b64'ad' is struct [Arr[i4]
  ad=some.Name dat       -- b64'ad' name "some.Name"  w/field "dat"
  zf:S&{ad} i2 I2        -- b64'zf' is struct [&my.Name i2 I2]
  zf=other.Name f1 f2 f3 -- b64'zf' name "other.Name" w/fields "f1" ...
```

## Constants

ZTy files also permit specifying constants. Unified constants are a common need
across languages and they have a very minimal syntactic surface.

```
const VERSION :i = "42";
const NAME    :s = "zoa";
```

The `:type` only supports `i` (number) or `s` (string). However
the type is only used as a hint for the language library/plugin,
all constants are stored as strings by the ZTy compiler and will
be strings when concatenated:

```
const DEC:i = 4;
const HEX:i = 0x4;

-- JOINED will be "dec=4 hex=0x4"
const JOINED:s = "dec=" $DEC " hex=" $HEX;
```

## Lua Implementation

The `zoa` module will also act as a function, `zoa(myRecord)` will type
check all fields and add a `string.pack` format string to `myRecord.__zoaf`
Any fields marked as an array will have `__zoaArr[field] = true`.

zoa will have functions for packing/unpacking zoa types with options for
encoding (alignment, endianness, etc). This can be built on top of to
create databases/etc.

[Civboot]: http://civboot.org
[packfmt]: https://www.lua.org/manual/5.3/manual.html#6.4.2
[base64url]: https://base64.guru/standards/base64url
