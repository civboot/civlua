# Ele: the Extendable Lua Editor

> WARNING: Ele and Shele are in the early design/implementation phase and are
> not even remotely useable.

Ele is an extendable, modal text editor written in Lua.

It ships with:

* A very basic text editor, also named Ele, which a user can extend with
  plugins.
* Shele, a "Lua shell" application which extends Ele with features useful
  for making it into a full-featured shell (think bash but better)

## Basic Architecture
Ele is architected using the MVI (model-view-intent) architecture, also known as
the "React architecture" from the web library of the same name.

```
model = Model.new{} -- holds all state
while true do
  -- update view and receive new events (no state modification)
  events = model:view()
  -- process events until empty (modifying model's state)
  model:update(events)
end
```

Where:
* `Model` represents all data needed to render a view as well as all
  (non-visibile) application state.
* `events` is a list of serializable (and human-readable) `Event` objects which
  are composed of plain-old-data (POD) which specify what the actor should
  handle the event and the data the event contains.
* The `update` function receives the `Model` and `Event` list and runs the
  suitable `Actor` until the event stream is empty.
  * actors can emit new events, which are handled (sequentially) before new
    events on the stack.
  * when an actor emits an event it increases the event depth. There is a limit
    on event depth/recursion (tentatively 12).
* The `view` function renders the screen at appropriate times and checks
  asynchronous state (user inputs, background processes, etc).

`Event` objects are created by:
* user inputs, primarily keyboard input
* background processes (timer, file watcher, etc)
* actions can emit new events (increasing the depth)

## Shele: a Lua shell

Shele is a shell built for the [Civboot] project in pure lua. It is shipped with
Ele because:

1. It was the primary inspiration for creating Ele
2. Like Ele it is small and it provides a good frame of reference on how to
   extend Ele for almost any application-specific purpose.


Basic goals:

 - use lua as a shell language
 - write commands like a (vi-style) text editor
 - execute a "block" with ctrl+enter.

A "block" is defined as text which is not separated by newlines.

```
-- a block (executed together with cursor on them and ctrl+enter)
sh'do something';  x = sh'do something else'
sh('do something '..x)

-- another block
sh'do another thing';  x = sh'do something else'
sh('do something '..x)
```

You can also use syntax to specify a "large" block that has whitespace.
Large blocks are executed with ctrl+shift+enter

```
--START
sh'do something';  x = sh'do something else'

sh('do something '..x)
--END
```

When a block is executed the following happens:

 - the paths to the stdout/stderr are appended
 - the user can use ctrl+o to open/close a view of them

What this looks like is:

```
-- a block (executed together with cursor on them and ctrl+enter)
sh'do something';  x = sh'do something else'
sh('do something '..x
-- MSG: error message or return code
-- OUT: /tmp/shele/akjbska-out
-- ERR: /tmp/shele/akjbska-err
```

When you use ctrl+o on (for example) the OUT line it jumps to the output file,
which you can navigate/copy/etc.

If you use (optional number)+t+enter on the OUT line it expands the tail
to the number given, or the system default (10 or so). Pressing t again
will close the block.

ctrl+h can be equivalently used to expand the head. Doing both will do both
and the info will say (head+tail)

```
-- a block (executed together with cursor on them and ctrl+enter)
sh'do something';  x = sh'do something else'
sh('do something '..x
-- MSG: error message or return code
-- OUT: /tmp/shele/akjbska-out (tail 2)
--[==[
  ... 100 lines ...
this is the end of the file
some error you want to see is here for example
]==]
-- ERR: /tmp/shele/akjbska-err
```

## Inspiration
The text editor [ple](https://github.com/philanc/ple/tree/master) was
inspirational due to it's simplicity and small size. Shele directly forked
it's `plterm.lua` file for getting started quickly.

