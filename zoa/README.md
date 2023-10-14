# Zoa: low level type definition and serialization

Zoa is a serialization and type framework inspired by protobuf and capnproto.
It's primary goals are:

* Specify types that are valid across language paradigms (especially C + Lua)
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
(types from packfmt not listed, such as "native length" types, are not supported).

```
  b: a signed byte (char)
  B: an unsigned byte (char)
  i[n]: a signed int with n bytes (default is native size)
  I[n]: an unsigned int with n bytes (default is native size)
  f: a float (IEEE single, 4 bytes)
  d: a double (IEEE double, 8 bytes)
  cn: a fixed-sized string with n bytes. Must be a reference
  z: a zero-terminated string
  s[n]: a string preceded by its length coded as an unsigned integer with n bytes. Note: n MUST be specified.
  x: one byte of padding
  Xop: an empty item that aligns according to option op (which is otherwise ignored)
  ' ': (empty space) ignored
```

> For Lua, `require'zoa'` adds the above types as metaty native types. This means
> they typecheck with "number", "string", etc.

In addition to native types, users can define their own `struct` (aka C struct)
and `enum` (aka C tagged union) types. This can be done in Lua by just calling
`zoa(myMetaType)` (from a metaty record or enum that uses only native types), or via zty syntax in a .zty file:

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

Zoa also defines a few standard types:

```
enum   ZTy         [ ... all native+standard zoa types ... ]
struct ZPair       [ str: ZTy, value: &ZTy ] -- typeid = 128
struct ZList       [ Arr[ZTy]                       ]
struct ZMap        [ Arr[ZPair]                     ]

struct ZDuration   [ I8 sec , U4 ns                 ]
struct ZTime       [ I8 sec , U4 ns                 ] -- since unix Epoch
struct ZDateTime   [ I4 year, U2 day, U4 sec, U4 ns ]
struct ZDate       [ I8 year, U2 day,               ]
struct ZYear       [ I8 year ]
```

> All zoa concrete types (not ZTy or ZPair) require a maximum of 16 bytes of space so the ZTy enum requires
wordsize+16 in storage.

## Serialization

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

Additionally, the following extensions to packfmt are available:
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
