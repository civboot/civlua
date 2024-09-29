
LUA_VERSION = lua
LUA = lua -e "require'pkglib'()"

.PHONY: ele

all: test demo

test: build
	mkdir -p ./.out/
	# make test
	$(LUA) test.lua
	# Tests complete

demo: build
	$(PRETEST) $(LUA) lib/vt100/demo.lua
	# $(PRETEST) $(LUA) cmd/ele/demo_term.lua

build: fd civix

fd: lib/fd/fd.c
	cd lib/fd && make build LUA_VERSION=$(LUA_VERSION)

civix: lib/civix/civix/lib.c
	cd lib/civix && make build LUA_VERSION=$(LUA_VERSION)

ele: build
	$(LUA) cmd/ele/ele.lua

doc:
	mkdir -p ./.out/
	$(LUA) civ.lua doc civ --pkg=deep --expand --to=.out/API.cxt
	$(LUA) civ.lua cxt.html .out/API.cxt API.html

clean:
	rm -f $$($(LUA) civ.lua ff -r --fpat='%.rockspec$$')
	rm -f $$($(LUA) civ.lua ff -r --fpat='%.src%.rock$$')

