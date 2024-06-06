# Architecture

Ele is architected using the MVI (model-view-intent) architecture, also known as
the "React architecture" from the web library of the same name.


```
   ,_____________________________________________
   | intent(): keyboard, timer, executor, etc    |
   `~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~'
   /\                                    || Data + events
   || Data + scheduled                   \/
  ,__________________   Data + scheduled ,____________________________
  | view(): paint    | <================ | model(): keybind, actions  |
  `~~~~~~~~~~~~~~~~~~'                   `~~~~~~~~~~~~~~~~~~~~~~~~~~~~'
```

The update loop (displayed above) is as follows:
* Receive a single intent: this can be a keyboard input, a timer firing or an
  operation function (async function) completing.
* Execute the model action tied to that event: aka the keybinding or a
  registered action. This will mutate Data depending on the event. It may also
  spawn some async opfns (operation functions)
* Paint the view/s (user-visible) and await the next intent

## Data
Data holds almost all the "state" for the application, as well as helper
methods. This includes:
* The `bufs` which has all open buffers
* The `root` View (and by extension all Views)
* The `keys` keybinding "plugin" (builtin)
* utility methods like `log()`

It does NOT include:
* `events` fifo buffer

## Actions
Actions are functions or `__call`-able tables which must be registered in
`ele.Actions` and must have signature:

```
function action([self,] data, ev, events)
```

The action body is free to mutate both `data` and `ev` as well as call
`events:push(newEvent)`. It is also free to call `lap.schedule(...)` to
schedule coroutines which call `events:push(newEvent)` asynchronously.

Any events scheduled directly by the action will be handled immediately (the LAP
executor will not be run). The actual implementation of `model()` is:

```
Ele.model = function(ele)
  local ev = ele.events:pop()
  while ev do
    Actions[ev.action or 'noaction'](ele.data, ev, ele.events)
    ev = ele.events:pop()
  end
end
```

The actual implementation of `intent()` is basically a specialized LAP executor
that calls `model()` when any `events` are present.

## Event Records
Event records MUST be POD (plain old data). This is asserted on by
`events:push`.

Events are a table with some fields defined, mainly:
 * action: the action name that should be executed. This must be
   registered in `ele.Actions`. See **Action** section above.
 * cause: (debugging only) a list of keys/etc that led to this action.
 * other data: used by the action function (this object is its second argument)

## Plugin Architecture
It is extremely simple to add plugins:

* register relevant `Actions` fields for your plugin. When an event with
  `action` is emitted then that action will be called by `model()`.
* (optional) initialize your plugin in `data`
* (optional) for listening to editor changes register with `ele.changes`, i.e.
  `push(ele.changes.fileOpened, myPluginFunction)`. It will be called like it
  is an action for such events.
* (optional) for listening to real events, schedule your plugin using
  `lap.schedule(...)` (i.e. the builtin `Keys` plugin does this).

## Keys Builtin Plugin {#keys}
There are several builtin actions, but they all center around `Keys` which
registers three objects:

* `Actions.keys` handles keys events
* `Data.keys` contains the current keys state
* `ele.bindings` contains the current keybindings (organized by mode) and
  related functions.
* it schedules a coroutine on the LAP scheduler which emits `action="keys"`
  events when keys are pressed.

`Data.keys` is architected to support both modal and chord style keybindings (aka vim
or emacs style). This means that when a user presses a single key the binding is
either executed (if it is an action) or the state is updated (if it is a chord)
or some other action is taken (if no binding is registered).

The fields of `Data.keys` are:

* `.default` is the "root" keybinding. This is a table of valid keyinput values
  (i.e. `a`, `^A`, `return`, etc) to either a function or a nested table of
  inputs.

* `.current` is the current keyinput table. This starts as `default` but changes
  as keys are entered.

When a keyinput is received `chord` is updated and the operation depends on
`keys.current`. If `keys.current` is a string then
`events:push(bindings[current](keys, current, chord))` is called.

> Why: this allows keybindings to set up "chains" where they wait for further
> inputs without having to modify and cache the mode. For example:
> `d<movement>` waits for the next command and emits an action that uses it to
> delete text until the movement.

Note that the called function may modify keys (i.e. to change `current`,
`default`, etc) but will NOT be able to modify other Ele data or events (besides
returning one). This makes the tie of keyinputs -> action more straightforward
as actions are only emitted when the chord is fully determined (though more
complex extensions can modify `keys` if necessary -- though this isn't
recommended in most cases).

Else `keys.current` must be a table and `value = keys.current[keyinput]`
* If value is a table then `.current` is set to that table (done)

* If value is a string then it refers to a registered member function of
  bindings:

  `events:push(bindings[value](keys, current, chord)`

* If the value is not found in `current` then the following event is pushed
  ```
  {action=Keys.unknown or 'chordUnknown'}
  ```
  This action handle the unknown key, also modifying `data.keys` appropriately
  (typically: `keys.current, keys.chord = keys.default, {}`)

