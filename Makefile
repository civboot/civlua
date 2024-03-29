
LP = "./?/?.lua;./pegl/?.lua;./civix/?.lua;./ele/?.lua;${LUA_PATH}"

.PHONY: ele

all: test

test: build
	mkdir -p ./.out/
	lua test.lua
	# LUA_PATH=${LP} lua civix/runterm.lua view 0.05
	# Tests complete

build: civix

civix: lib/civix/civix/lib.c
	cd lib/civix && make build

ele:
	LUA_PATH=${LP} lua ele/ele.lua

