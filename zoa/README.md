# Zoa: low level type definition and serialization

Zoa is a serialization and type framework inspired by protobuf and capnproto.
It's primary goals are:

* Specify types that are valid across language paradigms (especially C and Lua)
* Be able to serialize/deserialize types specified by Zoa to/from any language

Zoa is part of the [Civboot] project which aims to create a very simple while
very understandable software stack.

> zoa is named after "protozoa", which is itself a nod to [protobuf]. Yes, I'm
  aware protozoa are not fungi, but the name was too good.

## Zoa Types (.zty)

Zoa types are specified in a `.zty` file in the syntax below. They also have a
defined encoding in the Zoa Binary section and have minimalistic support
for constants in the constants section.

Zoa supports the following native types, which match Lua's [packfmt][packfmt]

```
  b: a signed byte (char)
  B: an unsigned byte (char)
  i[n]: a signed int with n bytes
  I[n]: a unsigned int with n bytes
  n[n]: a number(float) with n bytes
  s[n]: a counted string with n byte count.
```

* only n=1,2,4,8 are supported
* for number, only n=4,8 are supported.
* types from packfmt not listed, such as "native length" types, are not supported
* For Lua, `require'zoa'` adds the above types as metaty native types. This means they typecheck with "number", "string", etc. Other languages should act in a similar fashion.

Zty syntax also accommodates the following complex types:
* user-defined struct (aka C struct aka Product types) and enum (aka C tagged union aka Sum types), defined below.
* `&type` for a reference to a type. Multiple references are NOT supported (but can be achieved by wrapping in a struct).
* `A[type]` an array type, conceptually a length and a reference.

Users can define their own `struct`
and `enum` types in either ZTy syntax or using their language's zoa library.

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

Zoa also comes pre-defined with a few standard types. If your language already has these types, then you should implement the zoa interface for it or similar. The below shows their structure when serialized/deserialized:

```
enum   ZTy         [ all Zoa types ]
struct ZPair       [ str: ZTy, value: &ZTy ] -- typeid = 128
struct List       [ Arr[ZTy]                       ]
struct Map        [ Arr[ZPair]                     ]

struct Duration   [ I8 sec , U4 ns                 ]
struct Time       [ I8 sec , U4 ns                 ] -- since unix Epoch
struct DateTime   [ I4 year, U2 day, U4 sec, U4 ns ]
struct Date       [ I8 year, U2 day,               ]
struct Year       [ I8 year ]
```

> All zoa concrete types (not ZTy or ZPair) require a maximum of 16 bytes of space so the ZTy enum requires
wordsize+16 in storage.

## Serialization
The simplest version of serialization in Lua has no references or arrays and simply unwraps the type's fields and calls `string.pack` on it's concatenated format, with appropriate substitutions for float/etc.
Optional C compatibility can be achieved by adding appropriate `x` padding for alignment between structs. Simple deserialization is the reverse: unpack the string and then walk and set the fields from the resulting array.

The existence of references and/or arrays complicate things. Essentially every value must be given an index, and anything that references that value will instead reference the index. The basic structure is:

* every type is given an ity (type id) and every ity is given a name (which uses the metaty name).
  * ity=0 (when used below) refers to the "root type" and the actual ity encoded is also ity=0 (it is both ids)
  * when a value's ity=0 it is considered a "root value" and will be included in the output array.
    * see below for how ity are actually encoded.
* walk all values recursively. Every value behind a reference or contained in an array is put in a `table[value] = nextIdx()` where the idx is a number that increments. If the value is already in the table it is skipped.
* From now on, any references will use the idx to refer to the value.
* The values in this table are then serialized from idx high->low. Each value is prefixed by its ity (the types must be a known constant size)
* The remaining (non indirect) values are serialized.

Serialization is the reverse:
* items are deserialized into a table keyed by idx
* any references use the idx to lookup the value to determine the actual reference.
* the result is the final root values.

**rework the below**

The serialization format is intended for file storage and network transfer.
It is composed of two sections: (1) communicating the header containing type
information and (2) communicating the data. If the type information is already
known then it can be skipped.

The HEADER is first and contains the length in bytes of the header followed by the type specs.
The specs defkne the struct types, and use the same format as  Lua's [packfmt],
with the extensions below. The first elements must be
the endian and alignment values. **The maximum primary key value must fit inside the
maximum alignment**.

The type can be named (for debug only) with `b64Key=name/n`. The type is specified with `b64Key:X<tyspec>\n`.  where `X` is one of:

* `A` an array, the next value must be a single type
* `S` struct, the spec is the fields in-order.
* `E` enum, the spec is the variants in-order.

Additionally, the spec may contain following extensions to packfmt are available:
* `&ref` specifies a reference type, aka a primary key which can be zero (nil/missing).
* `{key}` specifies a b64 type id.

All Ids are encoded in base64-url ([base64])

Examples:
```
  ab:AB        b64'ab' type is array of unsigned bytes
  ab:Ai2       b64'ab' type is array of signed 2 byte integers
  ab:A{adf}    b64'ab' type is array of typeid=decode'adf' (defined elsewhere)
  ab=my.Name  b64'ab' type has string/debug name of "my.Name"
  zf:&{ab} i2 I2   struct [&my.Name,i2,I2]
  zf=my.structName name signed unsigned;  struct and field names separated by whitespace
```

## Constants

ZTy files also permit specifying integer and string constants. Unified constants
are a common need across languages and they have a very minimal syntactic
surface. Note that constants have no defined encoding.

```
const VERSION: U2 = 42
const NAME: D2 = "zoa"
```

The syntax is restrictive: numbers are only decimal or hex (`0x...`).

Strings are only `"my c\nstyle string"`.

Constants can refer to other previously defined constants via `$`. Joining a
string and a number is allowed, but it will be done verbatim, i.e.

```
const DEC = 4
const HEX = 0x4
const JOINED = "dec=" $DEC " hex=" $HEX --> "dec=4 hex=0x4"
```

This is intentionally restrictive: it is not good to get too clever with cross-language constants in a format like this.
If you want dynamic computation, use
a sandboxed Lua or your favorite
config language.

## Lua Implementation

The `zoa` module will also act as a function

`zoa(myRecord)` will add a `string.pack` format string to `myRecord.__zoaf`.
Note that the format string is simply all the fields and sub-fields appended
together, which is not C compatible (it doesn't add any unnecessary padding for
sub-structs).

> A C format string can be separately calculated but requires the alignment
> to be specified up-front.

Packing and unpacking is a simple matter:
* pack: `string.pack(alignStr..fmt, table.unpack(fields))`
* unpack: essentially the reverse is performed: `string.unpack` is called
  with the format string and the fields are extracted.

[Civboot]: http://civboot.org
[packfmt]: https://www.lua.org/manual/5.3/manual.html#6.4.2
[base64]: https://base64.guru/standards/base64url
