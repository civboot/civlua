# Zoa: low level type definition and serialization

Zoa is a serialization and type framework inspired by protobuf and capnproto.
It's primary goals are:

* Specify types that are valid across languages
* Be able to serialize/deserialize types specified by Zoa in any language

Zoa is part of the [Civboot] project which aims to create a very simple while
very understandable software stack.

> zoa is named after "protozoa", which is itself a nod to [protobuf]. Yes, I'm
 aware protozoa are not fungi, but the name was too good.

## Zoa Types (.zty)

Zoa types are specified in a `.zty` file in the syntax below. They also have a
defined encoding defined in the Zoa Binary section and have minimalistic support
for constants in the constants section.

Zoa supports the following native types which have a type-id assigned to them
sequentially (see the `Member` enum for their id)

```
    Ref: a reference to a type, possibly empty
    Arr: an array composed of a a length and reference
    None: used in ZTy
    D2: data (string) who's first two bytes are length and rest is data (no ptr)
    U1: 1 byte unsigned integer
    U2: 2 ...
    U4: 4 ...
    U8: 8 ...
    I1: 1 byte signed integer
    I2: 2 ...
    I4: 4 ...
    I8: 8 ...
```

In addition to native types, users can define their own `struct` (aka C struct)
and `enum` (aka C tagged union) types. The syntax is:

```
struct Owner; -- declare the type (defined later)
enum Cheese [ -- tagged union
  mozz        -- empty variant (just the id)
  cheddar     -- same
  other: Arr[U1]
]
cheeseAmount: U4 ] -- struct with one field of type U4
struct Pizza [
  owner: &Owner   -- reference to owner struct
  cheese: Cheese  -- field of previous type
  numPeperoni: U8 -- own field
]
struct Owner [ -- define pre-declared type
  store: Arr[U1],
  name: Arr[U1],
]
```

The following types are pre-defined and use reserved type ids of 64-255. `ZTy`
refers to an enum (valueSize=16) of all zoa types except ZPair.

```
struct ZPair       [ str: ZTy, value: &ZTy ] -- typeid = 128
struct ZList       [ Arr[ZTy]                       ]
struct ZMap        [ Arr[ZPair]                     ]

struct ZStr        [ Arr[U8]                        ]
struct ZDuration   [ I8 sec , U4 ns                 ]
struct ZTime       [ I8 sec , U4 ns                 ] -- since unix Epoch
struct ZDateTime   [ I4 year, U2 day, U4 sec, U4 ns ]
struct ZDate       [ I8 year, U2 day,               ]
struct ZYear       [ I8 year ]
```

## Serialization

The serialization format is intended for file storage and network transfer.
It is composed of two sections: (1) communicating the header containing type
information and (2) communicating the data. If the type information is already
known then it can be skipped.

A `.zb` file contains the following header, where "Bn" refers to unsigned
big-endian number of size n:
```
\x7FZOA  -- magic number
B1: bitmap
  b8:   endian    (0=network/big endian, 1=little endian)
  b5-6: pack-mode (0=align 1=alignC 2=packed)
  b4-1: ref Po2 ( 0b0011 = 2^3 i.e. 8 byte reference size)
U1: major version number (=0)
U2: minor version number (=0)
U4: HEADER size in bytes
U8: HEAP size in bytes
U8: VALUES size in bytes
HEADER
HEAP
DATA
B8/B8: 2nd heap+values
HEAP_2
DATA_2
... etc
```

Broadly:
* The HEADER has the (non-native) type definitions key'd by int or str
* The HEAP contains unstructured (but aligned) data referenced in VALUES
* TDATA contains data of type `HEADER.data`. The number of
  items is `len(DATA) / sizeof(HEADER.data)`
* More heaps and data can be added as-needed. Typically the file size
  will be doubled for each new section added.

> Any system can deserialize any data. If the endian and slot size match it
> gets the additional benefit that it can read the data directly into memory
> (replacing references with data read from the heap). Otherwise it requires a
> conversion step.


pack-mode:
* align = aligned, as if all fields and sub-fields were joined for `string.pack`
* alignC = align C, intentionally wasting space for C struct compliance
* packed = no alignment

### Serialization Process

Outside of HEADER there are no references to a value's type.

The HEAP is very similar to how values are stored in memory: as compactly as
possible and aligned according to any alignment requirements they have in
memory (C-aligned). Unused memory is set to the same byte value (typically 0's).

The DATA values COULD be stored so that fields (+ sub fields) are grouped together,
i.e. stored in a columnar format. This would save on data size and may be
supported in a future version. However, it would have cost when reading single
values from storage. Therefore it will be stored the same way as HEAP.

### Header

The header has the following types defined (using type-ids 129+). The HEADER
itself is composed of a single Header value, as shown below. If a type Key
is used byt not present in the header then it is expected to be known
system-wide.

```
enum Ty; -- defined later

IdxTy     [ idx: U4, ty: Ty ]
StrTy     [ str: D2, ty: Ty ]
enum ZKey [ idx: U4, key: D2 ]

struct Header [
  data: ZKey       -- the type in data
  idxs: Arr[IdxTy] -- types identified by integer
  keys: Arr[StrTy] -- types identified by string
]

enum Member [
  -- the member type is defined in HEADER
  idxTy: U4, idxArr: U4, idxRef: U4,
  strTy: D2, strArr: D2, strRef: D2,

  -- the member type is NATIVE
  None, D2,
  U1,   I1,
  U2,   I2,
  U4,   I4,
  U8,   I8

  -- the member type is pre-defined by Zoa
  ZPair, ZList, ZMap, ZStr,
  ZDuration, ZEpoch, ZDateTime, ZDate, ZYear
]

enum Ty [
  structTy [ Arr[Member] ], -- struct is array of fields
  enumTy   [ Arr[Member] ], -- enum   is array of variants
]
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
