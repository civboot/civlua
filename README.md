# Civboot Lua Modules

This is the repository for civboot-owned Lua modules.

These are developed together but kept in separate modules so that others can
pick and choose the pieces they want to use for their own projects.

See the sub-directories for the individual documentation. A suggested order
might be:

* [civ.lua](./civ.lua): a self-loading lua module which acts as
    a hub for civboot scripts. See [Installation](#Installation)
    for details.
* [ff](./civ.lua): find and fix files. Kind of like a supercharged
  `find`, `grep` and pattern subtitution all rolled into a simple
  203 line script.
  * `ff -r --pat='OldTest([Cc]lass)' --sub='NewTesting%1' --mut`
    to rename OldTestClass -> NewTestingClass in all files,
    where the 'c' is not case-sensitive (but preserved)
* [shim](./shim/README.md): write scripts for Lua, execute from shell (57 LoC)
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

## Installation
[civ.lua](./civ.lua) is a self-contained, self-loading lua module.
Simply put this `civlua` directory anywhere and execute it on
unix and it will work.

> Bash recommendation: `alias ,=/path/to/civ.lua`
>
> Now execute sub-commands like:
>
> `, ff -r --pat=recursive`

## Work In Progress

* [ele](./ele/README.md): Extendable Lua Editor
  * Modal, similar to Vim
  * Currently incomplete, but 2181 LoC with core functionality
* `patience/` is to implement a patience diff, be patient!

## LICENSE

This software is released into the public domain, see LICENSE (aka UNLICENSE).
