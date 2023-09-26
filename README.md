# Civboot Lua Modules

This is the repository for civboot-owned Lua modules.

These are developed together but kept in separate modules so that others can
pick and choose the pieces they want to use.

See the sub-directories for the individual documentation. A suggested order
might be:

* [metaty](./metaty/README.md): runtime type system.
* [gap](./gap/README.md): a simple and powerful line-based Gap buffer.


## TODO:

* gap should use `__index` and `__len` instead of it's own functions.
