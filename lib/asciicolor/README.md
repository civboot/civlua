# asciicolor: encode text color and style with a single ascii character

**TODO**: this module is being ported from vt100 and is not ready for use.

asciicolor is a protocol which encodes text color in terminals and (in future)
elsewhere using only a single ascii character: i.e. **b** for black, **w** for
white and **n** for navy blue, etc. Capitalizing the character encodes a style
(bold for foreground, underlined for background).

The following is all of the ascii colors. 
```
Ascii Colors. Capitalized means: fg=bold bg=underlined
  z = 'zero', [' '] = 'zero', [''] = 'zero', -- aka default.

  --  (dark)           (light)
  b = 'black',         w = 'white',
  d = 'darkgrey',      l = 'lightgrey',
  r = 'red',           p = 'pink',
  y = 'yellow',        h = 'honey',
  g = 'green',         t = 'tea',
  c = 'cyan',          a = 'aqua',
  n = 'navy',          s = 'sky', -- blue
  m = 'magenta',       f = 'fuschia',
```

> Note: These map to the available colors in a VT100 terminal emulator,
> See the vt100 module for that implementation.

In addition, writer objects which conform to asciicolor should implement
the following methods:

* `colored` field which returns true if color is supported (and can be set to
  false to turn off color)
* `acinset(l, c, str, fg, bg)`: similar to `lines.inset()` except provides `fg` and
  `bg` strings that can be nil (for no color) or must be strings with the same
  length as `str` and set the foreground and background color of `str`
* `acwrite(fg, bg, str, ...)`: same as `file:write(str)` except `fg, bg` sets
  the color of str just like `acinset`. Additional strings passed to `...` are
  not styled.
* `acsub(...span) -> str, fg, bg` like `lines.sub` except returns the fg and bg
  ascii colors as well.

`asciicolor.File` is a helper type which implements the logic necessary for
writing color to a typical terminal-like interface via its `acwrite()` method.

## How to Use
The programmer uses this protocol by having a separate set of text (file,
buffer, grid, etc) for the text itself as well as the foreground and background
colors.

