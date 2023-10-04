# Picker

> **WARNING**: not currently functional.

The picker API aims to make working with structured lua data ergonomic and
performant. It uses a fluent API like so:

```
data = {
  A{a1='one',   a2=1},
  A{a1='two',   a2=2},
  A{a1='three', a2=3},
}
twoThree = query(A)
  .a2:any{2, 3}
  .a1:eq('two')
res = twoThree(data)
```

The idea is that the query can directly execute on structured data, as shown.
However, it can also work with indexed data:

```
idx = Indexer{A, data, a1='hash', a2='hash'}
res = idx:query(twoThree)
```

When you build an `Indexer` you tell it which fields to index on. When a query
is executed it will use the optimal solution based on what indexes are
available.

The indexes are stored where the keys (to a table, sorted array, etc) are the
"indexed" field and the values are a (sorted) list of the indexes where that
value can be found.

`field="hash"` optimizes the following:
* `eq` uses it directly as the list of valid indexes
* `any` unionions the indexes.

`index="sort"` optimizes the following:
* `any` and `eq` uses binary search to find the indexes just like hash (but
  slower)
* `lt` (less than), `gt` (greater than), etc for ordered types use a binary
  search index and then select the side of the list which match the condition.

