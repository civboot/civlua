
LUA_VERSION = lua
LUA_EX = $(LUA_VERSION)
LUA = $(LUA_EX) -e "require'pkglib'()"

.PHONY: ele

all: test demo

test: build
	which $(LUA_EX)
	mkdir -p ./.out/
	# make test
	$(LUA) test.lua
	# Tests complete

demo: build
	$(PRETEST) $(LUA) ui/vt100/demo.lua
	# $(PRETEST) $(LUA) cmd/ele/tests/test_term.lua

build: ds fd pod civix smol

fd: lib/fd/fd.c
	cd lib/fd && make build LUA_VERSION=$(LUA_VERSION)

ds: lib/ds/*.c lib/ds/*.h
	cd lib/ds && make build LUA_VERSION=$(LUA_VERSION)

pod: lib/pod/pod.c
	cd lib/pod && make build LUA_VERSION=$(LUA_VERSION)

civix: lib/civix/civix/lib.c
	cd lib/civix && make build LUA_VERSION=$(LUA_VERSION)

smol: lib/smol/smol.c
	cd lib/smol && make build LUA_VERSION=$(LUA_VERSION)
	# cd lib/smol && make test  LUA_VERSION=$(LUA_VERSION)

ele: build
	$(LUA) cmd/ele/ele.lua

doc:
	mkdir -p ./.out/
	$(LUA) civ.lua doc civ pkg --pkg=deep --expand --to=.out/README.cxt
	$(LUA) civ.lua cxt.html .out/README.cxt README.html --config=PKG.lua

clean:
	rm -f $$($(LUA) civ.lua ff r:lib r:ui r:cmd f:'%.rockspec$$')
	rm -f $$($(LUA) civ.lua ff r:lib r:ui r:cmd f:'%.src%.rock$$')

