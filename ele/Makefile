
all: test

LP = "./?.lua;../civlua/?/?.lua;../civlua/civix/?.lua;${LUA_PATH}"

test:
	mkdir -p out/
	LUA_PATH=${LP} lua tests/test_motion.lua
	LUA_PATH=${LP} lua tests/test_gap.lua
	LUA_PATH=${LP} lua tests/test_buffer.lua
	LUA_PATH=${LP} lua tests/test_action.lua
	LUA_PATH=${LP} lua tests/test_model.lua

run:
	LUA_PATH=${LP} lua ele.lua

installlocal:
	luarocks make rockspec --local

uploadrock:
	source ~/.secrets && luarocks upload rockspec --api-key=${ROCKAPI}
