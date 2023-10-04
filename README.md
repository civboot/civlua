# Civboot Lua Modules

This is the repository for civboot-owned Lua modules.

These are developed together but kept in separate modules so that others can
pick and choose the pieces they want to use for their own projects.

See the sub-directories for the individual documentation. A suggested order
might be:

* [metaty](./metaty/README.md): runtime type specification and checking (457 LoC)
  * Auto type formatting
  * Auto type equality (depth comparison)
* [ds](./ds/README.md): absurdly necessary data structures and algorithms (341 LoC)
* [civtest](./civtest/README.md): absurdly simple test libray (66 Loc)
* [civix](./civix/README.md): Lua linux and shell library (392 LoC) 
* [pegl](./pegl/README.md): recursive descent parsing language (430 LoC `pegl.lua`)
  * PEG-like but Lua-only syntax
  * 214 LoC for Lua's syntax definition (`./pegl/pegl/lua.lua`)

> LoC are from 2023-10-03 using `tokei ?/?.lua ?/?/` where `?` is the folder name

## Work In Progress

* `patience/` is to implement a patience diff, be patient!

## LICENSE

This software is released into the public domain, see LICENSE (aka UNLICENSE).
