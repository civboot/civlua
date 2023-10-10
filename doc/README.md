# doc: documentation of lua's core types

Allows you to do `, doc io.close` and get brief documentation on the API.

The `doc` module simply registers a brief bit of documentation (via
`metaty.docty`) to all core Lua types that need documentation.

The intended audience is developers who already know how to use a function but
need a reference. The function signature is always included, as well as special
strings or patterns. For example:

* `string.find` includes all the character classes
* `io.open` includes the different modes
* `io.close` includes the return type.

For a full reference manual see: https://www.lua.org/manual

For tutorial style documentation you should look at
https://www.lua.org/pil/contents.html

Doc is intentionally non-exahustive and should not try to be a tutorial.
