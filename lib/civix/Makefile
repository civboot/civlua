# Copy/pastable Makefile for Lua C sources.
#
# Note: `luarocks make` puts the shared library files next to the C file,
#       which is the convention followed here.

# Modify these for a new library
NAME  = civix
FILES = $(NAME)/lib.c
OUT   = $(NAME)/lib
test: build
	lua test.lua

UNAME := $(shell uname)
build:  $(UNAME)
Linux:  $(OUT).so
Darwin: $(OUT).so
# Windows: $(OUT).dll
	
$(OUT).so: $(FILES)
	make Build$(UNAME)

BuildLinux: $(FILES)
	$(CC) $(FILES) $(shell pkg-config lua --cflags --libs) -shared -o $(OUT).so

BuildDarwin:
	$(CC) $(FILES) $(shell pkg-config lua --cflags) -c -O2 -fPIC   -o $(OUT).o
	$(CC) $(OUT).o -bundle -undefined dynamic_lookup -all_load     -o $(OUT).so

# BuildWindows: TODO

clean:
	rm -f $(OUT).o $(OUT).so $(OUT).dll
