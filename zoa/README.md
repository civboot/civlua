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

In addition to native types, users can define their own `struct` (aka C struct)
and `enum` (aka C tagged union) types. The syntax is:

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

Types are encoded as integer ids. Ids 0-63 are reserved for zoa native types (i.e. b, i3, s2),
Ids 64-255 are used for Zoa standard types defined below. 

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

All zoa types (except ZTy) require a maximum of 8 bytes of space so the ZTy enum requires
wordsize+8.

## Serialization

The serialization format is intended for file storage and network transfer.
It is composed of two sections: (1) communicating the header containing type
information and (2) communicating the data. If the type information is already
known then it can be skipped.

The HEADER is first and contains the length of the header followed by the data.
The data defines the struct types, and uses the same format as  Lua's [packfmt],
with the extensions of `[array]`, `&ref;` and `#key;`. The first elements must be
the endian and alignment values. **The maximum primary key value must fit inside the
maximum alignment**.

* `@array` specifies an array type, aka a length and a primary key
* `&ref` specifies a reference type, aka a primary key which can be zero (nil/missing).
* `#key;` specifies a name

All Ids are encoded in base64-url ([base64])

Examples:
```
  ab:@B;        decode'ab' type is array of unsigned bytes
  ab:@i2;       decode'ab' type is array of signed 2 byte integers
  ab:@(adf);    decode'ab' type is array of typeid=decode'adf' (defined elsewhere)
  ab=(my.Name)  decode'ab' type has string/debug name of "my.Name"
```

pack-mode:
* align = aligned, as if all fields and sub-fields were joined for `string.pack`
* alignC = align C, intentionally wasting space for C struct compliance
* packed = no alignment

## Constants

ZTy files also permit specifying integer and string constants. Unified constants
are a common need across languages and they have a very minimal syntactic
surface. Note that constants have no defined encoding.

```
const VERSION: U2 = 42
const NAME: D2 = "zoa"
```

The syntax is restrictive: numbers are only decimal or hex (`0x...`).

Strings are only `"my c\nstyle string"` Multiple strings can be put
next to eachother.

Constants can refer to other previously defined constants via `$`. Joining a
string and a number is allowed, but it will be done verbatim, i.e.

```
const DEC = 4
const HEX = 0x4
const JOINED = "dec=" $DEC " hex=" $HEX --> "dec=4 hex=0x4"
```

This is intentionally restrictive: it is not good to get too clever with
constants.

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
