## Navigation

### Opening files

Note: A filelist buffer is just a normal temporary buffer which contains a list
of files. It also overrides "enter" to perform a goto on the line.

The `goto(string)` function does the following. If it finds a file it opens it
in an edit buffer. If it finds a directory it opens it in a filelist buffer.
* Before any of these, if there is a language syntax matcher (i.e. ctags, lsp,
  etc) then attempts to defer to that.
* First, attempts to goto the literal string, i.e. `some/path.txt`.
* Second, removes front/back whitespace and tries again
* Third treats it like code: and searches for something like
  `(import|include )? "(?some/kind/of/path.lua)"?`
* Fourth, uses the above path and determines whether it is `path/like` or `import.like`
  and tries the above again -- but this time walks the path putting an error
  message for unfound elements but going to whatever it CAN find.
  * For instance `import foo.bar.MyClass.myMethod;` would open "MyClass.java"
    and would post an error message for the missing "myMethod".

Vim-like bindings:
* `g f` goto file under cursor which is obtained by parsing the line.
* `g F` same as above but uses trailing numbers to get a line number

Space-f (find) bindings:
* `space f f`: open an interactive search buffer that uses fd to
  find files that match the name in the current directory.
* `space f space`: open a list buffer in CWD
* `space f .`: open a list buffer in the current file's directory

