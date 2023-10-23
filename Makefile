
LP = "./?/?.lua;./pegl/?.lua;./civix/?.lua;./ele/?.lua;${LUA_PATH}"

.PHONY: ele

all: test

test:
	mkdir -p ./.out/
	lua test.lua
	LUA_PATH=${LP} lua civix/runterm.lua view 0.05
	# Tests complete

run_term:
	LUA_PATH=${LP} lua civix/runterm.lua $(mode) $(period)

ele:
	LUA_PATH=${LP} lua ele/ele.lua
