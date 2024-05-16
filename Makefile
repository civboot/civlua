
LUA_VERSION = lua
LUA = lua -e "require'pkglib':install()"

.PHONY: ele

all: test

test: build
	mkdir -p ./.out/
	$(PRETEST) $(LUA) test.lua
	# lua civix/runterm.lua view 0.05
	# Tests complete

build: fd civix

fd: lib/fd/fd.c
	cd lib/fd && make build LUA_VERSION=$(LUA_VERSION)

civix: lib/civix/civix/lib.c
	cd lib/civix && make build LUA_VERSION=$(LUA_VERSION)

ele:
	LUA_PATH=${LP} lua ele/ele.lua

clean:
	rm -f $$($(LUA) civ.lua ff -r --fpat='%.rockspec$$')
	rm -f $$($(LUA) civ.lua ff -r --fpat='%.src%.rock$$')
	rm -f $$($(LUA) civ.lua ff -r --fpat='%.o$$')
	rm -f $$($(LUA) civ.lua ff -r --fpat='%.so$$')
