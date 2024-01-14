# Civboot Lua Modules

This is the repository for [Civboot]-owned Lua modules and software.

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

These libraries and tools are developed together but kept in separate modules
(individually uploaded to [LuaRocks]) so that others can pick and choose the
pieces they want to use for their own projects. Together they (will) form a
complete development environment with some awesome shell/lua commandline
scripting tools, and even form the basis of both assemblers and a Lua compiler
written in Lua. See [Installation](#Installation) for ways to install the
command utilities.

This directory is split into `cmd` for user-executable commands and `lib` for
libraries.

* [civ.lua](./civ.lua): a self-loading lua module which acts as a hub for
  civboot scripts.
* [shim](./lib/shim/README.md): write scripts for Lua, execute from shell (57
  LoC)
* [metaty](./lib/metaty/README.md): runtime type specification and checking (457 LoC)
  * `help()` function for viewing documentation on any module or type
  * Auto type formatting
  * Auto type equality (depth comparison)
* [ds](./lib/ds/README.md): absurdly necessary data structures and algorithms (341 LoC)
* [civtest](./lib/civtest/README.md): absurdly simple test libray (66 Loc)
* [civix](./lib/civix/README.md): Lua linux and shell library (392 LoC) 
* [pegl](./lib/pegl/README.md): recursive descent parsing language (430 LoC `pegl.lua`)
  * PEG-like but Lua-only syntax
  * 214 LoC for Lua's syntax definition (`./pegl/pegl/lua.lua`)
* [ff](./cmd/ff/README.md): find and fix files. Kind of like a supercharged
  `find`, `grep` and pattern subtitution all rolled into a simple
  203 line script.
  * `ff -r --pat='OldTest([Cc]lass)' --sub='NewTesting%1' --mut`
    to rename OldTestClass -> NewTestingClass in all files,
    where the 'c' is not case-sensitive (but preserved)

> LoC are from 2023-10-03 using `tokei ?/?.lua ?/?/` where `?` is the folder name

## Work In Progress

* [ele](./cmd/ele/README.md): Extendable Lua Editor
  * Modal, similar to Vim
  * Currently incomplete, but 2181 LoC with core functionality
* `patience/` is to implement a patience diff, be patient!

## Installation
Some civlua packages are uploaded to [LuaRocks] and can be installed with:

```
luarocks install <some-pkg> --local
```

An alternative (recommended even) method is to simply download this directory
and add it to the following paths in your shell's `rc` file:

```
LUA_PATH="/path/to/civlua/lib/pkg/pkg.lua;...rest-of-your-LUA_PATH"
LUA_PKGS="/path/to/civlua;...rest-of-your-LUA_PKGS"
```

> If you use [LuaRocks] you can replace the `LUA_PATH` above with
> `luarocks install pkg --local`

### Bash recommendation:

```
alias ,=/path/to/civ.lua
```

Now execute sub-commands like:

```
, ff -r --pat=recursive
```

## Future
I blog about future goals and design ideas at
https://github.com/civboot/civboot/tree/main/blog

## Development
Run tests with
```
make test
```

Running tests currently requires [luaposix], but most libraries work without it.

**All contributors must agree to license their contributions into the public
domain.**

## LICENSE
This software is released into the public domain, see LICENSE (aka UNLICENSE).

Attribution is appreciated but not required.

[Civboot]: http://civboot.org
[pkg.lua]: https://luarocks.org/modules/vitiral/pkg
[LuaRocks]: https://luarocks.org/
[luaposix]: https://github.com/luaposix/luaposix
