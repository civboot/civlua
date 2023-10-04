
The editor is architected with the MVI (model-view-intent) architecture, also
known as the "react" architecture. This architecture relies on a "stream" of
serializable (human-readable) events that are handled sequentially, with all
state change occuring as the result of handling events.

The basic architecture is:

```
model = Model.new{}
events = List{}
while true do
    model:update(events)  -- process events until empty
    events = model:view() -- asyncronous view and event receiving
end
```

Where:
* `Model` represents all data needed to render a view as well as all
  (non-visibile) application state.
* `events` is a list of serializable (and human-readable) `Event` objects which
  are composed of plain-old-data (POD) which specify what the event is and
  what data it contains.
* The update function receives the `Model` and `Event` list and runs the
  suitable handlers until the event stream is empty.
  * handlers can emit new events, which are handled (sequentially) before new
    events on the stack.
  * when a handler emits an event it increases the event depth. There is a limit
    on event depth (tentatively 12). Essentially this implements "event
    recursion" with a limit on the depth.
* The `view` function renders the screen at appropriate times and checks
  asynchronous state (user inputs, background processes, etc).

`Event` objects are created by:
* user inputs, primarily keyboard input
* background processes (timer, file watcher, etc)
* update methods can emit new events


## Bindings and Chain
The `bindings` are provided by (bascically) a nested Map of valid keys:

```
model.bindings = {
  'a': Action(name='append', fn=function(mdl) ... end,
  'leader': {
    'a': Action(name='leader.add', fn=...),
  }
}
```

When a key is pressed:
- look in `chord` or `bindings` for the key (and cleanup chord if not)
 - if mapped to an action then call the `fn`
 - if mapped to another Bindings map then set `chord` to that.
 - if mapped to Chain then set `chain` to that.

If the `action.fn` returns additional events they are executed until empty.

If `chain` is set then future events will be handled by `chain.fn` until it
returns `nil` (when `chain` will be set back to `nil`). If it returns a new
chain then that will be used instead.

The purpose of the chain is for chords like `dta` (delete till 'a').
The "delete" action has to accept a movement event from the _next_ action
and the "till" action has to accept a single rawKey value.


