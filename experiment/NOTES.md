(reverse chronological order notes)

## 2024-04-30 refactor

Also: discussions and useful links
* https://www.reddit.com/r/lua/comments/1cgwn2y/thoughts_on_making_modules_own_name_global/
* lua performance: https://www.lua.org/gems/sample.pdf#page=3

I'm taking a break, leaving the repo in a bit of a bad state

First of all, I've removed `metaty.record`, replacing with `metaty.record2` --
however PEGL isn't yet migrated, so that needs to happen first.

After that is complete I have a MAJOR overhaul in mind:

* pkg exports a few globals: `mod, DOC_LOC, DOC_NAME`. Move them from metaty.lua where
  I've done an MVP implementation.
  * this is a new standard called the PKG standard.
  * Basically, libraries will now do: `local M = mod and mod'name' or {}`
  * The user can select whether to use `pkg` or `require` with
    `alias lua="lua -e \"require = require'pkglib'\""` (or similar in Make/etc)
  * mod will then handle naming and updating `SRC*` globals
* PKG.lua: make dirs just a boolean, if true PKG.dirs is loaded which is a list of subpkgs
* can call metaty module direction instead of metaty.record2
* `civ.lua` overrides global `print  metaty.eprint`. I'm sick of dealing with that.
* new module: `batteries`. Once required it adds/overrides several globals.
  Should only be used in scripts and cmd line.
  * print, eprint
  * metaty, ds
  * yield, resume, `coroutine.__call` (creates coroutine)
  * push, pop, popk, extend, update, copy
  * table.reverse
  * f (metaty.format), assertf, errorf 
  * split, lines, path
  * add to os: dir, mono, sleep, pathty
* ds: remover iter
* metaty
  * add Fmt.to and create fmtOut and fmtErr and pfmtErr
  * use them for print/eprint/eprintf
  * move assertf/errorf to use metaty.format
* PKG.lua should specify test files and I should use them
* Overhaul how testing is done: global `T`
  * Tests are defined with `T.foo = function() T.assertEq(1, 1) end`
    The simplest implementation just runs the function immediately
  * `lua -e 'require = require'pkglib'; T = require"civtest"' myTest.lua`

