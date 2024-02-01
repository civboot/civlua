
test: build
	lua test.lua
	
build: civbase.c
	gcc civbase.c -c -Wall -llua5.3 -I/usr/include/lua5.3
	gcc civbase.o -shared -o libcivbase.so
