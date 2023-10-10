# doc: documentation of lua's core types

Allows you to do `, help io.close` and get brief documentation on the API.

The `doc` module simply registers a brief bit of documentation (via
`metaty.docTy`) to all core Lua types that need documentation.

The intended audience is developers who already know how to use a function but
need a reference. The function signature is always included, as well as special
strings or patterns. For example:

* `string.find` includes all the character classes
* `io` documents all the types in the io module

For a full reference manual see: https://www.lua.org/manual

For tutorial style documentation you should look at
https://www.lua.org/pil/contents.html

> Note: Docs are intentionally brief and minimal.

Contributions welcome. All contributions must be in the public domain (like this
library is).
