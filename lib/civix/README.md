# Civix: Lua linux and shell library

Civix is a thin wrapper around a small C library (`civix/lib.c`) which uses
[metaty] and [ds] types. It provides:

* `epoch` ([ds].Epoch) and `mono` ([ds].Mono) functions
* `sh` which executes a shell command (`execv`) in a separate thread.
  The std[in,out,err] pipes can then be interacted with either synchronously or
  asynchronously.
* `async` module which provides asynchronous:
  * sleep
  * file operations (read, write, seek) which can be used on standard lua
    files.
    * File operations use a global thread pool. This is initialized when
      first importing `civix.async` with the number of threads set via
      `civix.setIoThreads`, which you can set before importing `civix.async`.


```
assertEq('on stdout\n', sh[[ echo 'on' stdout ]].out)
assertEq(''           , sh[[ echo '<stderr from test>' 1>&2 ]].out)
assertEq('<stderr from test>',
  sh([[ echo '<stderr from test>' 1>&2 ]], {err=true}).err)
assertEq("foo --bool --bar='hi there'\n",
         sh{'echo', 'foo', bool=true, bar='hi there'})
```

[metaty]:   ../metaty/README.md
[ds]:       ../ds/README.md
