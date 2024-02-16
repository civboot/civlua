
test: build
	lua test.lua
	
build: civnative.c
	gcc civnative.c -c -Wall -llua5.3 -I/usr/include/lua5.3
	gcc civnative.o -shared -o civnative.so
