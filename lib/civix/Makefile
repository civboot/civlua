# Copy/pastable Makefile for Lua C sources.
#
# Note: `luarocks make` puts the shared library files next to the C file,
#       which is the convention followed here.

# Modify these for a new library
NAME  = civix
FILES = $(NAME)/lib.c
OUT   = $(NAME)/lib
LUA_VERSION = lua

UNAME != uname
build:  $(UNAME)
NetBSD: $(OUT).so
Linux:  $(OUT).so
Darwin: $(OUT).so
# Windows: $(OUT).dll

$(OUT).so: $(FILES)
	make Build$(UNAME)

BuildNetBSD:
	$(CC) -DBSD $(FILES) -fPIC -l$(LUA_VERSION) -I/usr/pkg/include/$(LUA_VERSION) -shared -o $(OUT).so

BuildLinux: $(FILES)
	# vcmd:       $(_VCMD)
	# vcmd2:      $(_VCMD2)
	# lua version $(LUA_VERSION)
	$(CC) $(FILES) -fPIC -l$(LUA_VERSION) -I/usr/pkg/include/$(LUA_VERSION) -shared -o $(OUT).so

BuildDarwin:
	$(CC) $(FILES) $(shell pkg-config lua --cflags) -c -O2 -fPIC   -o $(OUT).o
	$(CC) $(OUT).o -bundle -undefined dynamic_lookup -all_load     -o $(OUT).so

# BuildWindows: TODO

clean:
	rm -f $(OUT).o $(OUT).so $(OUT).dll
