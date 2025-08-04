#ifndef FD_H
#define FD_H
#include <lua.h>
#include <unistd.h>
#include <pthread.h>

#define LUA_FD    "FD"
#define LUA_FDT   "FDT"

typedef struct _FD {
  volatile int fileno;
  volatile int code; // 0==ready/done/ok, negative=started, positive=error
  volatile int ctrl;   // control input (function specific)
  volatile off_t off;  // offset (used for seek)
  volatile off_t pos;  // position we report (in buffer)
  volatile off_t fpos; // actual file position
  volatile size_t size, si, ei; // buffer: size, start index, end index
  volatile char* buf;
} FD;

typedef struct _FDT {
  FD fd;
  pthread_t th;
#if __APPLE__
  int socks[2]; // write socks[0] to unblock, read socks[1] waits
#else
  int evfd; // eventfd
#endif
  volatile int stopped;
  volatile void (*meth)(FD*);
} FDT;

__attribute__ ((visibility ("default"))) FD*  FD_create(lua_State* L);
FDT* FDT_create(lua_State* L);

__attribute__ ((visibility ("default"))) void FD_close(FD*);
void FDT_destroy(FDT*);

#endif
