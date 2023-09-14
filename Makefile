
LP = "./?/?.lua;${LUA_PATH}"

all: test

test:
	mkdir -p out/
	lua metaty/tests/test_utils.lua
	lua metaty/tests/test_records.lua
	lua ds/tests/test_ds.lua
	lua gap/tests/test_gap.lua

	lua metaty/tests/test_generic.lua
