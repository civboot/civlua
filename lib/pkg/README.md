# pkg: better lua package creation and importing

Lua pkg improves lua's module management over the build-in `require` function
while also acting as a command which generates `name-version.rockspec` files.

How to import packages:
* Add the path to `path/to/pkg/?.lua` on your `LUA_PATH`
* Put the directories containing your lua pks somewhere on `LUA_PKGS`
  environment variable (`;` separated)
* execute lua like `lua -e "require'pkglib'.install()"`

> Recommendation for `.bashrc`:
>
> ```bash
> alias luap="lua -e \"require'pkglib'.install()\""
> ```

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

Example:

```
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
Because `LUA_PATH` is clumsy and annoying.

Luarocks is awesome, but it doesn't solve local path management. Also,
`rockspec` is very opinionated on file names and I wanted a way to auto
generate the `.rockspec` files.

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
