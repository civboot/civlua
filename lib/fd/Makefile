# Copy/pastable Makefile for Lua C sources.

# Modify these for a new library
NAME  = fd
FILES = $(NAME).c $(NAME).h
OUT   = $(NAME)
LUA_VERSION = lua

UNAME := $(shell uname)
build:  $(UNAME)
Linux:  $(OUT).so
Darwin: $(OUT).so
# Windows: $(OUT).dll
	
$(OUT).so: $(FILES)
	make Build$(UNAME)

BuildLinux: $(FILES)
	$(CC) $(FILES) -fPIC -l$(LUA_VERSION) -I/usr/include/$(LUA_VERSION) -shared -o $(OUT).so

BuildDarwin:
	$(CC) $(FILES) $(shell pkg-config lua --cflags) -c -O2 -fPIC   -o $(OUT).o
	$(CC) $(OUT).o -bundle -undefined dynamic_lookup -all_load     -o $(OUT).so

# BuildWindows: TODO

clean:
	rm -f $(OUT).o $(OUT).so $(OUT).dll

