#ifndef FD_H
#define FD_H
#include <lua.h>
#include <unistd.h>

#define LUA_FD    "FD"
#define LUA_FDT   "FDT"

typedef struct _FD {
  int code; // 0==ready/done/ok, negative=started, positive=error
  int ctrl; // control input (function specific)
  int fileno; off_t pos;
  size_t size, si, ei; // buffer: size, start index, end index
  char* buf;
} FD;

FD* FD_create(lua_State* L);

#endif
