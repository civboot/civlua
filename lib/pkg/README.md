# pkg: create and import lua packages

Basic usage is to update your `.bashrc` with:

```
LUA_PATH="path/to/pkg/?.lua;etc..."
LUA_PKGS="path/to/mod1;path/to/mod2;etc..."
alias luap="lua -e \"require'pkglib'.install()\""
```

Now when you run `luap` your `require'something'` will search for the
'something' pkg in `LUA_PKGS` (or subpkgs they define). Note: it will still
fallback to `require` if the pkg is not found.

This has several advantages:

* local development: set `LUA_PKGS=./` and it will only search for pkgs in
  your current directory. You can define a `PKG.lua` with a `pkgs` variable to
  recursively search for other locally defined packages.
* concise `LUA_*` environment variables: you no longer have to maintain a huge
  and impossible to read `LUA_PATH` variable.
* performance: the `PKG.lua` locations are cached for future lookup

## Library Authors

How to create packages:
* Add a `PKG.lua` in your library's root.
* Define global variables for the required fields:
  * `name`: the name of your package (`package` in [rockspec])
  * `version`: [rockspec] version string, i.e `"0.1-5"`
  * `url`: url to the source code, i.e. `"git+http://github.com/civboot/civlua"`
  * `srcs`: source files to include relative to pkgs, either in path form (`mod.lua`)
    or in keyval form (`mod = 'path/to/mod.lua'`).
  * `dirs`: causes pkg search to continue in the given sub-directories.
    Can be used to construct trees of packages.
  * `rockspec`: (optional) provide starting rockspec when generating it

Example `PKG.lua` file:
```lua
name    = 'myLib'
version = '0.1-5'
url     = 'git+http://github.com/civboot/myLib'
srcs    = {
    'myLib.lua',      -- name: myLib
    'myLib/sub1.lua', -- name: mylib.sub1
    ['myLib.sub2'] = 'lib/myLib/submodule.lua'},
}
```

[rockspec]: https://github.com/luarocks/luarocks/wiki/Rockspec-format

## Why?
I am personally using this library to maintain 10+ projects at
[civlua](http://github.com/civboot/civlua) and will be making a `pkgrock`
cmd utility to help me.

## How?
`PKG.lua` files are executed in a sandbox. Their environment has access to only
the following, which are in their global variables:

```
UNAME   LIB_EXT -- examples: "Linux",".so"  "Windows",".dll"
string.format
table.insert  table.sort  table.concat
pairs   ipairs
error   assert
```

> Note: PKG.lua files can use `format(...)` but not `string.format(...)`. It is
> this way to prevent accidentally leaking values into the `string` table, etc.

The globals the script creates are then read as the configuration.
