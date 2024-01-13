# pkgrock: luarocks for [pkg]
Script to auto create and upload luarocks from PKG.lua files.

Example (using `civ.lua`)
```
, rock lib/pkg --create --gitops='add commit tag' \
  --gitpush='origin main --tags' --upload=$ROCKAPI
```

[pkg]: https://github.com/civboot/civlua/tree/main/lib/pkg
