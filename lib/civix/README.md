# Civix: linux tool library

Civix contains standard linux functions that exist in most language's "sys"
library such as `sleep`, `epoch`, etc. It also contains a powerful `Sh{}` type and
convieience `sh()` function for executing system shell commands, either
synchronously or asynchronously using the LAP protocol (see
[lib/lap](../lib/lap))

```
$ lua
> sh = require'civix'.sh
> -- cat /var/log/syslog | grep "netgroup: version"
> out = sh{stdin=io.open'/var/log/syslog', 'grep', 'netgroup: version'}
```

[metaty]:   ../metaty/README.md
[ds]:       ../ds/README.md
