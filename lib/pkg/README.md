# pkg: local and recursive require

Basic usage is to update your `.bashrc` with:

```
LUA_PATH="path/to/civlua/lib/pkg/?.lua;..."
LUA_PKGS="path/to/pkg1;path/to/pkg2;..."
alias luap="lua -e \"require'pkglib'.install()\""
```

Your libraries (packages) should have a `PKG.lua` in their root:
```lua
name    = 'myLib'
version = '0.1-5'
url     = 'git+http://github.com/civboot/myLib'
srcs    = {
    'myLib.lua',      -- name: myLib
    'myLib/sub1.lua', -- name: mylib.sub1
    ['myLib.sub2'] = 'lib/myLib/submodule.lua'},
}
pkgs = {
  'path/to/subpkg/',
}
```

Now when you run `luap` your `require'myLib'` will search for 'myLib' pkg in
`LUA_PKGS` (or subpkgs they define). Note: it will still fallback to `require`
if the pkg is not found.

This has several advantages:

* local development: set `LUA_PKGS=./` and it will only search for pkgs in
  your current directory. You can define a `PKG.lua` with a `pkgs` variable to
  recursively search for other locally defined packages.
* concise `LUA_PKGS` environment variables: you no longer have to maintain a huge
  and impossible to read `LUA_PATH` variable.
* performance: the `PKG.lua` locations are cached for future lookups whereas
  `LUA_PATH` must search every path every time.


## PKG Protocol
pkg exports a few OPTIONAL global variables. Other libraries which override
`require` or want to create self-documenting code are encouraged to use these
in the following way in order to support both normal and pkglib environments:

* `local G = G or _G` to define/get undefined globals in a typosafe way
  * pkglib overrides `_G` so that access to **undefined** globals throws an
    error (fixing Lua's biggest mistake). Note that **defined** globals behave
    normally with no performance penalty.
  * Usage: `G.myGlobal = G.myGlobal or true` will define the global `myGlobal`
    as `true` if it is not already defined.
* `local M = mod and mod'myModName' or {}` to initialize your module. This
  enables self-documenting modules.
* `G.MAIN = G.MAIN or M` should be run before you `require` other libraries, but
  only if your module is runnable from the command line.
  * Why: later (at the bottom of your script) you can do
    `if M == MAIN then M.main(arg); os.exit(0) end` to make your library run as
    a script when called directly.
  * This is never required for libraries. It is REQUIRED if your script can be
    run from the command line and installs pkg-protocol libraries in it's
    dependency tree, as many libraries behave differently when called directly
    (i.e. they will run a command and exit).

Example module template:
```
#!/usr/bin/env -S lua -e "require'pkglib'()"
--- this module is now self documenting. See the documentation
--- of it or any sub-item with: [$doc 'myModName.item']
local M = mod and mod'myModName' or {} -- self-documenting module
local G = G or _G                            -- typosafe globals
G.MAIN = G.MAIN or M                   -- (cmdline script only)

--- docs for myFn
M.myFn = function() ... end --> returnType

--- docs for main function when run directly
M.main = function(args)
  ... use as a script
end

-- run as a script
if M == MAIN then M.main(arg); os.exit(0) end

return M -- return as a library
```

See also: [../doc](../doc/README.md)

## For Library Authors

To define a pkg you just need to add a `PKG.lua` file in your library's root
which defines the following globals 
* `name`: the name of your package (maps to `package` in [rockspec])
* `version`: [rockspec] version string, i.e `"0.1-5"`
* `url`: url to the source code, i.e. `"git+http://github.com/civboot/civlua"`
* `srcs`: source files to include relative to pkgs, either in path form (`mod.lua`)
  or in keyval form (`mod = 'path/to/mod.lua'`).
* `dirs`: causes pkg search to continue in the given sub-directories.
  Can be used to construct trees of packages.
* `rockspec`: (optional) provide starting rockspec when generating it

> Note: you don't need to use `G` for `PKG.lua` files as it's run in a sandbox.

[rockspec]: https://github.com/luarocks/luarocks/wiki/Rockspec-format


## Why?
I am personally using this library to maintain 10+ projects at
[civlua](http://github.com/civboot/civlua). PKG files can be converted
to rockspec using `./civ.lua pkgrock --help`


## How do `PKG.lua` files work?
`PKG.lua` files are executed in a sandbox. Their environment has access to only
the following, which are in their global variables:

* `pairs ipairs error assert`
* from string: `format`
* from table: `insert sort concat`
```
It also has the globals `UNAME, LIB_EXT` which can be values such as
`"Linux",".so"` or `"Windows",".dll"` and are for loading C libraries.

> Note: PKG.lua files can use `format(...)` but not `string.format(...)`. This
> prevents accidentally leaking values into the `string` table, etc.

Any globals that a PKG.lua script defines are used as the configuration (see
"For Library Authors" section).
