
LP = "./?/?.lua;${LUA_PATH}"

all: test

test:
	mkdir -p out/
	lua metaty/tests/test_records.lua
	lua gap/tests/test_gap.lua
