# LAP: Lua Asynchronous Protocol

LAP is a lightweight zero-dependency asynchronous protocol. It is architected to
allow libraries to provide a lightweight "asynchronous mode" so that they can be
used asynchronously by a coroutine executor. This allows users and library
authors to write code that looks synchronous but which can be executed
asynchronously at the application author's discression.

The LAP protocol has two components:

* yielding protocol: An ultra simple yet optionally-performant to communicate
  with the executor loop (example: see `lap.Lap`)
* two global tables which libraries can use to schedule coroutines (`LAP_READY`)
  and register their asynchronous API (`LAP_FNS_ASYNC` and `LAP_FNS_SYNC`)

Library authord **do not** need to depend on this library to work with the
LAP protocol. Library authors can fully support the protocol by following the
Yielding Protocol below and copy/pasting the following:

```lua
LAP_FNS_SYNC  = LAP_FNS_SYNC  or {}
LAP_FNS_ASYNC = LAP_FNS_ASYNC or {}

// register functions to switch modes, see end of lap.lua for example
table.insert(LAP_FNS_SYNC,  function() ... end)
table.insert(LAP_FNS_ASYNC, function() ... end)

// implement your asynchronous functions by following the protocol.
```

This folder also contains the `lap.lua` library, see the Library section.

Library authors should make their default API **synchronous** by default,
except for items that don't make sense (example: see Send/Recv which will fail
if yield is attempted).

## `LAP_READY` Global Table
The `LAP_READY` table keys are the coroutines which should be run. The values
are not used by the executor and are typically either `true` or a debug
identifier of some kind.

This means that a coroutine can schedule another coroutine `cor` by simply doing
`LAP_READY[cor] = true`. This simple feature can be used for many purposes such
as creating Channel datastructures as well as handling any/all behavior. See
the Library section for details.

## Yielding Protocol
LAP's yielding protocol makes it trivial for Lua libraries to interface with
executors. Libraries can simply call `coroutine.yield` with one of the following
and the executor will perform the behavior specified if it is supported (else it
must run the coroutine on the next loop).

* `yield(nil)` or `yield(false)`: forget the coroutine

* `yield(true)` or `yield"ready"`: run the corroutine again as soon as possible.
  * Should prevent the executor loop from sleeping.
  * Equivalent to: `LAP_READY[coroutine.running()] = true; coroutine.yield()`

* `yield("sleep", sleepSec)`: run the coroutine again after `sleepSec` seconds
  (a float).

* `yield("poll", fileno, events)`: tell the coroutine to use unix's
  `poll(fileno, events)` syscall to determine when ready.

* Other yield values may be defined by application-specific executors.
  If the executor doesn't recognize a value it can either throw an error or
  treat it as `true` (aka "ready"), depending on the application requirements.

## Global Variables

There are four global variables:

* `LAP_READY`: contains the currently ready coroutines for the executor loop to
  resume.
* `LAP_FNS_SYNC` / `LAP_FNS_ASYNC`: contains functions to switch lua to synchronous /
  asynchronous modes, respectively.
* `LAP_ASYNC`: is set to true when in async mode to determine behavior at
  runtime.

The sync/async tables allows a user to write code in a blocking style yet it can
be run asynchronously, such as the following. You can even switch back and forth
so that tests can be run in both modes.

```
function getLines(path, fn)
  local lines = {}
  for line in io.lines(path) do
    table.insert(lines, line)
  end
  return lines
end
```

> Recomendation: use `lap.async()` and `lap.sync()` to switch modes.

## `lap` Library (see [lap.lua](./lap.lua))
The (pure lua) `lap` library implements:

* `lap.Lap(...)` default implementation of a single loop in an executor.

* `lap.Any` and `lap.all` for interacting with lists of coroutines.

* `lap.channel()` which creates the `Recv` and `Send` channel types to send
  values between coroutines.

* `lap.async()` / `lap.sync()`: switches all registered libraries to
  async/sync mode (just calls every function in `LAP_FNS_(SYNC/ASYNC)`)
