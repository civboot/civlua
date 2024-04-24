# Copy/pastable Makefile for Lua C sources.
#
# Note: `luarocks make` puts the shared library files next to the C file,
#       which is the convention followed here.

# Modify these for a new library
NAME  = civix
FILES = $(NAME)/lib.c
OUT   = $(NAME)/lib
DEPS  = -I../fd
LUA_VERSION = lua

UNAME := $(shell uname)
build:  $(UNAME)
Linux:  $(OUT).so
Darwin: $(OUT).so
# Windows: $(OUT).dll
	
$(OUT).so: $(FILES)
	make Build$(UNAME)

BuildLinux: $(FILES)
	# vcmd:       $(_VCMD)
	# vcmd2:      $(_VCMD2)
	# lua version $(LUA_VERSION)
	$(CC) $(FILES) $(DEPS) -fPIC -l$(LUA_VERSION) -I/usr/include/$(LUA_VERSION) -shared -o $(OUT).so

BuildDarwin:
	$(CC) $(FILES) $(DEPS) $(shell pkg-config lua --cflags) -c -O2 -fPIC   -o $(OUT).o
	$(CC) $(OUT).o -bundle -undefined dynamic_lookup -all_load     -o $(OUT).so

# BuildWindows: TODO

clean:
	rm -f $(OUT).o $(OUT).so $(OUT).dll
