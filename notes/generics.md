## Generics

I have a VERY initial version of generics working, with almost no testing except
to make sure the basic plumbing works. I need to take a 6 month break from
personal projects as I can't focus on anything else while I work on this.

For basic usage see "Generic Types" in `metaty.lua` (at commit d5db3b4)

The basic process is that `Checker.gen` holds the names of all currently defined
genvars (`g'A'` has name "A"). As it type checks it updates the current
definition of these, which are used for further type checking. This works
because for LOTS of types you control the generic names, i.e. you can write:

```
local MapWithVals = record'Map'
    :generic'K' :generic'V'
    :generic'V'
    :field{'vals', Table{I=g'V'}}

Map.add = Fn{g'K', g'V'}
Map.pop = ... other functions
```

You always get to choose the names of your sub-members because NONE of your
sub-members should be generic (there should be an assertion for exactly this
point).

The first challenge comes in when you instantiate a generic choice (i.e.
`MapWithVals{K='string', V='number'}`).  Firstly, we HAVE to make a copy of the
MapWithVals (and all it's functions), so that you can use it for your concrete
type's metatable

> Some of the cost of this is reduced with singletons tracked by the GENERICS
> trie.

However, we can avoid making a deep copy if we use the concept of an `anchor`.
When running the type checker (recursively) it would use the concrete selection
of MapWithVals as the anchor, then when type-checking any of the function args
it would use the anchor to lookup the type values.

The reason this works is because when you defined MapWithVals you had complete
control of all the generic variable names! As soon as you cross the "boundary"
of another concrete type you must then use that types generic variable names.

Anyway, that was the theory. I haven't yet put it into practice -- and I won't
for some time from now.

