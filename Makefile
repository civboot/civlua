
LP = "./?/?.lua;./pegl/?.lua;./civix/?.lua;${LUA_PATH}"

all: test

test:
	mkdir -p out/
	lua metaty/test.lua
	lua civtest/test.lua
	lua ds/test.lua
	               lua pegl/tests/test_pegl.lua
	LUA_PATH=${LP} lua pegl/tests/test_lua.lua
	# lua patience/test.lua
	lua civix/test.lua
	LUA_PATH=${LP} lua civix/test_term.lua
	LUA_PATH=${LP} lua civix/runterm.lua view 0.05
	# Tests complete

run_term:
	LUA_PATH=${LP} lua civix/runterm.lua $(mode) $(period)

