# vt100: terminal interface library

This is Civboot's VT100 terminal interface library. It implements (and also
defines) the API that civboot terminal emulators must implement to be considered
Civboot compliant.

It has the following core types and constants:
* `Term` object, see below
* `AsciiColor` which is a map from single ascii lowercase characters to the
  color name (i.e. `w -> white`). These can be used in Term.fg and Term.bg to
  set the relvant colors.
* `FgColor` and `BgColor` contains a map from the color name to the VT100 color
  code (for external libraries).
* Various key utility functions and maps for checking and working with the
  values sent by `Term:input()`

To be civboot compliant the `Term` type exported must have the following API:
* `ds.Grid` fields `text, fg, bg` for terminal text, foreground color and
  background color respectively
* `l, c` fields for setting the cursor location (which is drawn)
* `h, w` (height width) fields (see `resize()`)
* `:input(keysend)` method which asyncronously (LAP) sends any user-inputed keys
* `:draw()` method which draws the text
* `:resize()` method that (if nothing is passed to it) retrieves the `h, w`
  fields and updates and clears child grids.
* `:clear()` method which clears all child grids.
* `run` boolean (default=true) which can be set to false to stop related
  coroutines (best effort)

