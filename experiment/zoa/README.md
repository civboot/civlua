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
  c[n]: a bytearray with size n bytes
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
enum ZTy; -- declared, defined below
struct Error [ code:U2 mlen:B msg:c13 ]
struct List       [ Arr[ZTy]                       ]
struct ZPair      [ key: ZTy  value: ZTy           ]
struct Map        [ Arr[ZPair]                     ]
struct Range [ start:I8  count:U4  period: I4 ]
struct Duration   [ I8 sec , U4 ns                 ]
struct Time       [ I8 sec , U4 ns                 ] -- unix Epoch
struct DateTime   [ I4 year, U2 day, U4 sec, U4 ns ]
struct Date       [ I8 year, U2 day,               ]
struct Year       [ I8 year ]
struct IPV4       [ addr:c4  port:U2  hasPort:U1  ]
struct IPV6       [ i1:I2 i2:I2 ... i8:I2 ]

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
`idx`), and when serialized all references will instead use the `idx`. The `idx`
is simply the byte-position of the referenced value in the data stream starting
from `1` (`0==null`). For serializing, we must also prefix every value with the
type (so that we can know its size) and if it's an array we must know its length
as well.  To accomplish this there will be a HEADER that contains all the type
specs, each of which will have an `ity` (type id). See HEADER for that
structure.

The basic serialization is:

* walk all values recursively. Every value behind a reference is put in a
  `tableK[value] = true and also `table.insert(tableI, value)`. If the value is
  already in `tableK` then it is skipped.
* The values in `tableI` are then serialized in reverse order, with their byte
  position stored in `tableK`. When serialized, each value is prefixed by its
  `ity` (the types must be a known constant size) and if it's an Array it also
  has the encoded length.
* From now on, any references will use the `idx` to refer to the value.
* The remaining root values are serialized using `ity=0`

Deserialization is the reverse:
* Items are deserialized into a table keyed by idx
* Any references use the idx to lookup the value to determine the actual reference.
* The result is the final root values (`ity=0`)

### HEADER of itys (type ids)

The HEADER is structured as a series of `ity:packfmt\n` to define the type and
`ity=name field1name field2name\n` to define the name and field/variant names.
`ity` is an integer encoded as [base64url], `packfmt` is the same as that
defined in the **Zoa Types** section with the following additions:

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

itys start at 1023. The following ity's are reserved
* 0 is the root type
* 1 is Arr type (encodes length)
* 2-63 for native types
* 64-127 for zoa std (Range, Duration, etc)
* 128-1023 reserved

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

The `zoa` module will also act as a function, `zoa(myRecord)` will type-check all fields and add a `string.pack` format string to `myRecord.__zoaf`
Any fields marked as an array will have `__zoaArr[field] = true`.

zoa will have functions for packing/unpacking zoa types with options for
encoding (alignment, endianness, etc). This can be built on top of to
create databases/etc.

## File Database Architecture (rough)
zoa is intended for use in a file-database. The basic architecture is:

* The Op type below will be ity=0, the "real" root type is `&Root`
* Appending non-Op (`ity~=0`) to the database effectively causes no change
  (to the columns).
* appending an Op (ity=0) modifies the database (i.e. it is a single transaction)

```
struct Op [
  add: Arr[&Root],
  del: Arr[&Root],
]
```

That is how data is STORED. A separate file and/or in-memory process then keeps an index of:
* An in-order list of root values and whether they are alive (`.zbi`)
* specific fields it wants to lookup performantly (details TBD but basically a
  large hash table pointing to the root idx's which match).

Cleanup of a zoa file database (i.e. eliminating unused idx's) is done by
* constructing a bitmap of all idx's (all values and sub-values), as well as
  their types
  * note: the types are necessary since the type information may be embedded
    in a field/etc.
* perform a mark-and sweep GC using the bitmap to find dead ones
* keep a lookup table of live -> new and rebuild the file without dead indexes
* additional compactness can be gained with a separate hash table to dedup
  idx+ity values.

[Civboot]: http://civboot.org
[packfmt]: https://www.lua.org/manual/5.3/manual.html#6.4.2
[base64url]: https://base64.guru/standards/base64url
