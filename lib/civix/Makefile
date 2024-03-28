FILES = civix/lib.c

UNAME    := $(shell uname)
LUA_ARGS := $(shell pkg-config --cflags --libs lua)

ifeq ($(UNAME), Linux)
  LIBTYPE = shared
  LIBEXT  = so
else ifeq ($(UNAME), Darwin)
  LIBTYPE = dynamiclib
  LIBEXT  = dylib
endif
	
build: $(FILES)
	$(CC) -$(LIBTYPE) $(FILES) -o civix/lib.$(LIBEXT) $(LUA_ARGS)
