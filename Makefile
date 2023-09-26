
LP = "./?/?.lua;${LUA_PATH}"

all: test

test:
	mkdir -p out/
	# metaty
	lua metaty/test.lua
	# ds
	lua ds/tests/test_ds.lua
	# gap
	lua gap/tests/test_gap.lua
