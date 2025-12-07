# civ.lua: a minimalist self-documenting tech stack for Civboot

> **NOTICE**: this code is in a bit of turmoil as I develop the civ build
> system. Much of the documentation is also incorrect.

I am currently overhauling the code with the new "civ build system"
(the `civ.lua` file as a command). If you wish to hack on it, the following
is roughly how that is done:

```sh
export LOGLEVEL=INFO
lua bootstrap.lua init         # create .civconfig.lua

# run bootstrapped tests with log output.
LOGLEVEL=INFO lua bootstrap.lua boot-test

# install civ in ~/.local/civ/
lua bootstrap.lua install civ:

# After following the directions regarding PATH variables run:

# install civ + ff command
civ install civ: civ:cmd/ff  # install software
ff p:'%.lua$' HOME           # run find-fix command
```

Needed items to make this code hackable again:
* Add the ability to define and run tests:
  *  `sys/lua/test.luk`
  *  `civ test` subcommand
* Finish porting all the `PKG.lua` files to the new form (see `lib/ds/PKG.lua`
  for new form)
* Remove makefiles and lib/pkg -- they aren't needed anymore, I've kept them as
  reference for now but they will go away soon.
* Rearchitect the documentation output. I want text-documentation to go in `civ/doc/...`
  and have the ability to generate more structured (not single-page) documentation
  to an html-like site, but I need to explore my options.

---

You can see previous rendered Developer/API documentation by going to
**[this link][rendered]** or by downloading this repository and going to
`file:///home/path/to/civlua/README.html` directly in your browser.

[rendered]: https://html-preview.github.io/?url=https://github.com/civboot/civlua/main/README.html


