# vt100: terminal interface library

This is Civboot's VT100 terminal interface library. It implements (and also
defines) the API that civboot terminal emulators must implement to be considered
Civboot compliant.

Civboot terminal libraries must have the metatable type `Term` with the
following API:

* is a list (rows) of lists (columns). Each column MAY have a single unicode
  character set.
* has `h, w` (height width) read-only fields
* has an `grid [ds.Grid]` field
  * must handle backfill if previous columns are `nil`
  * must handle newlinesin the str, inserting into `l+1, l+2` etc for each line,
    all starting at the same column.
* has a `:draw()` method which draws the text, then sets `h, w`
