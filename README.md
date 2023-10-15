# Civboot Lua Modules

This is the repository for civboot-owned Lua modules and software.

```bash
cd civlua/
LUA_PATH="?/?.lua"
$ alias ,="$PWD/civ.lua"  # NOTE: can now execute from anywhere!
, help math        # core lua math
, help table       # core lua table
, help ds          # civlua datastructure module
, help ds.Duration # help on inner type

# Execute awesome tiny tools
$ , ff -r %recursive
./README.md
     1: * [pegl](./pegl/README.md): recursive descent parsing language (430 LoC `pegl.lua`)
     2: > `, ff -r --pat=recursive`
./pegl/README.md
     1: # PEGL: PEG-like recursive descent Parser in Lua
     2: PEGL is PEG like recursive descent Parser written in Lua.
... etc
```

These libraries and tools are developed together but kept in separate modules so
that others can pick and choose the pieces they want to use for their own
projects. Together they (will) form a complete development environment with some
awesome shell/lua commandline scripting tools, and even form the basis of both assemblers and a Lua compiler written in Lua. See [Installation](#Installation)
for how to install (just copy this directory).

Each sub-directory has individual documentation. A suggested reading order
might be:

* [civ.lua](./civ.lua): a self-loading lua module which acts as
    a hub for civboot scripts.
* [shim](./shim/README.md): write scripts for Lua, execute from shell (57 LoC)
* [metaty](./metaty/README.md): runtime type specification and checking (457 LoC)
  * `help()` function for viewing documentation on any module or type
  * Auto type formatting
  * Auto type equality (depth comparison)
* [ds](./ds/README.md): absurdly necessary data structures and algorithms (341 LoC)
* [civtest](./civtest/README.md): absurdly simple test libray (66 Loc)
* [civix](./civix/README.md): Lua linux and shell library (392 LoC) 
* [pegl](./pegl/README.md): recursive descent parsing language (430 LoC `pegl.lua`)
  * PEG-like but Lua-only syntax
  * 214 LoC for Lua's syntax definition (`./pegl/pegl/lua.lua`)
* [ff](./civ.lua): find and fix files. Kind of like a supercharged
  `find`, `grep` and pattern subtitution all rolled into a simple
  203 line script.
  * `ff -r --pat='OldTest([Cc]lass)' --sub='NewTesting%1' --mut`
    to rename OldTestClass -> NewTestingClass in all files,
    where the 'c' is not case-sensitive (but preserved)

> LoC are from 2023-10-03 using `tokei ?/?.lua ?/?/` where `?` is the folder name

## Work In Progress

* [ele](./ele/README.md): Extendable Lua Editor
  * Modal, similar to Vim
  * Currently incomplete, but 2181 LoC with core functionality
* `patience/` is to implement a patience diff, be patient!

## Installation
[civ.lua](./civ.lua) is a self-contained, self-loading Lua module.
Simply copy this `civlua` directory anywhere and execute it on
unix and it will work.

> Bash recommendation: `alias ,=/path/to/civ.lua`
>
> Now execute sub-commands like:
>
> `, ff -r --pat=recursive`

Running tests currently requires [luaposix], but most libraries work without it.

[luaposix]: https://github.com/luaposix/luaposix
## Future
I blog about future goals and design ideas at
https://github.com/civboot/civboot/tree/main/blog

## LICENSE

This software is released into the public domain, see LICENSE (aka UNLICENSE).
