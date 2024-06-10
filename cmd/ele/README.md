# Ele: Extendable Lua Editor

Ele is an (**In Development**) extendable lua editor. This is the second
rewrite, with the original code being in [experiment/ele](../experiment/ele).

Ele's primary goals are:
* Implemented in a minimal amount of understandable code. It is the main editor
  for [civboot]
* Enjoyable and extendable for developers to fit their workflow
  * undo/redo, syntax highlighting, plugins, user-configurable bindings
    (supports vim/emacs style), etc.
* Implements a lua shell (zsh competitor)
* Can handle any size text file

Non-goals of Ele are:
* focusing on performance against the other goals

See [ARCH.md](ARCH.md) for the current architecture.

[civboot]: https://github.com/civboot/civboot

## LICENSE
This software is released into the public domain, see LICENSE (aka UNLICENSE).

Attribution is very appreciated (but not required).
