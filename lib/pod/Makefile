# Copy/pastable Makefile for Lua C sources.

# Modify these for a new library
NAME  = pod
FILES = $(NAME).c
OUT   = $(NAME)
LUA_VERSION = lua

UNAME != uname
build:  $(UNAME)
NetBSD: $(OUT).so
Linux:  $(OUT).so
Darwin: $(OUT).so
# Windows: $(OUT).dll

WNO = -Wno-incompatible-function-pointer-types

$(OUT).so: $(FILES)
	make Build$(UNAME)

# test: $(FILES)
# 	$(CC) ds_test.c -l$(LUA_VERSION) -I/usr/include/$(LUA_VERSION) -o smol_test
# 	./ds_test

BuildNetBSD: BuildLinux
BuildLinux: $(FILES)
	$(CC) $(FILES) -fPIC -l$(LUA_VERSION) -I/usr/include/$(LUA_VERSION) -shared -o $(OUT).so

BuildDarwin:
	$(CC) $(FILES) $(shell pkg-config lua --cflags) -c -O2 -fPIC $(WNO)
	$(CC) $(OUT).o -bundle -undefined dynamic_lookup -all_load     -o $(OUT).so

# BuildWindows: TODO

clean:
	rm -f $(OUT).o $(OUT).so $(OUT).dll smol_test

