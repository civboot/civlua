
LP = "./?/?.lua;./pegl/?.lua;./civix/?.lua;./ele/?.lua;${LUA_PATH}"
LUA_VERSION = lua

.PHONY: ele

all: test

test: build
	mkdir -p ./.out/
	$(PRETEST) lua test.lua
	# LUA_PATH=${LP} lua civix/runterm.lua view 0.05
	# Tests complete

build: fd civix

fd: lib/fd/fd.c
	cd lib/fd && make build LUA_VERSION=$(LUA_VERSION)

civix: lib/civix/civix/lib.c
	cd lib/civix && make build LUA_VERSION=$(LUA_VERSION)

ele:
	LUA_PATH=${LP} lua ele/ele.lua

