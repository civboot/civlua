# Smol: compression algorithms in Lua
Small is a collection of public domain compression algorithms written in pure
Lua.

**WARNING**: currently these are VERY non-performant and are primarily for
educational purposes. Likely some version of them will eventually be included in
Civboot, but will probably require some pieces to be re-written in a more
low-level language.

## LZW

LZW is a fantastically simple compression algorithm. Basically the encoder
builds a dictionary of codes mapped to words it has seen one character at a
time. The decoder uses the same process to build the dictionary from the codes
emitted.

A high level architecture is:
1. start with a dict of all possible byte values (0-0xFF)
2. set word=''
3. walk the input char `c`. Keep building `word = word..c` until it is not in dict.
4. Each time `word..c` is not in dict:
  1. emit the known `dict[word]` (code of word w/out c)
  2. set `dict[word..c] = nextCode; nextCode++`
  2. set word = c

This means that the ONLY codes emitted are:
1. the base codes 0-255
2. codes previously emitted
3. special case: nextCode, see below.

The special case 3 is this: a non-previously emitted code will be emitted
without ever having been emitted before in the case where we have re-built the
previous word plus its first character. In that case we never actually emitted
the code of prevWord! Fortunately for us, this will simply cause us to emit
`nextCode-1` so we can handle this special case in the decoder!

This condition is fairly rare (it occurs only 8 times in a 1MiB file of text),
but it is important we handle it. We can force it to happen quickly by
controlling the input.

Let's take a look at how this works in practice with an input of
`a b b b a b a` (ignore spaces)

Let's also build up our code dictionary as only three characters:
`codes[a=1, b=2, c=3]; nextCode=4`

```
    input  word       case           emit code'text'           next word + code
    code
    -----+-----------+--------------+-------------------------+-----------
   1  a -> w = 'a'    IS known,                                w='a'  c   c=4
   2  b -> w = 'ab'   is NOT known:  emit 1'a';  codes[ab]=4;  w='b'      c=5
   3  b -> w = 'bb'   is NOT known:  emit 2'b';  codes[bb]=5;  w='b'      c=6
   4  b -> w = 'bb'   is known,                                w='bb'
   5  a -> w = 'bba'  is NOT known:  emit 5'bb'; codes[bba]=6; w='a'      c=7
   6  b -> w = 'ab'   is known, skip                           w='ab'
   7  a -> w = 'aba'  is NOT known:  emit 4'ab'; codes[aba]=7  w='a'      c=8
```

Note that we always emit codes prevoiusly known until we emit 5...  which
we have never emitted! However, because 5 == nextCode (on the decoder) it
knows the exact shape of the data is `word + word(first char)`

The decoder must build-up it's dictionary while also decoding the input.
The decoder receives codes. The first code will always be 0-255, so it
emits the `char(code)` and sets `word=char(code)` It then walks the
input codes `code`. For each code
  1. if code==nextCode then `entry = word + (word first char)`
        this is the special case above.
     else `entry = dict[code]`
  2. emit `entry` to the output
  3. set `dict[nextCode] = word + (entry first char)`
  4. set `word = entry` for next loop

And that's it for the base algorithm. In reality you need to limit the maximum
code size to a power-of-2 (so exit the dict-building part when the limit is
hit) and then encode+decode the packed bitstream of codes (which ds.BitFile
will help with). Other than that, this is it!

A few important points while building the dictionary:
1. Every time the encoder emits a code it adds a dictionary entry
1. Every time the decoder decodes a code (except the first) it adds a dictionary
   entry.

The above is kind of profound: there is never a wasted code, every code
contributes to the dictionary until the dictionary is full. It also makes the
algorithm incredibly simple to implement.

## Huffman Encoding
Orthogonal to LZW is Huffman encoding. While LZW compresses common sequences
into single codes, Huffman represents common codes as short bitprefixes and
less-common codes as long bit-prefixes.

Huffman works by constructing an unbalanced binary tree where the leaves are
the codes. The "huffman code" is then the bits needed to get from the root
to the leaf, where `0` represents left and `1` represents right. We will call
this the `bitpath`.

To construct the tree so that the end codes take up the least number of bits,
the Huffman technique uses a priority queue (a minheap) where the value is the
frequency of the code. Each time nodes are added to the tree, their bitpath
is increased by one. The node that is the sum of their frequencies is then
put back into the minheap and the process continued until there is only
a single node in the minheap.

