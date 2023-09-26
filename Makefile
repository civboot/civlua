
LP = "./?/?.lua;${LUA_PATH}"

all: test

test:
	mkdir -p out/
	lua metaty/test.lua
	lua civtest/test.lua
	lua ds/test.lua
	lua gap/test.lua
	lua patience/test.lua
