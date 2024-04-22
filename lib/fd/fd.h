#ifndef FD_H
#define FD_H
#include <lua.h>
#include <unistd.h>
#include <pthread.h>

#if __APPLE__
#include <dispatch/dispatch.h>
typedef dispatch_semaphore_t fdsem_t;
#else
#include <semaphore.h>
typedef sem_t fdsem_t;
#endif

#define LUA_FD    "FD"
#define LUA_FDT   "FDT"

typedef struct _FD {
  int code; // 0==ready/done/ok, negative=started, positive=error
  int ctrl; // control input (function specific)
  int fileno; off_t pos;
  size_t size, si, ei; // buffer: size, start index, end index
  char* buf;
} FD;

typedef struct _FDT {
  FD fd;
  pthread_t th; fdsem_t sem;
  volatile int stopped;
  volatile void (*meth)(FD*);
} FDT;

FD*  FD_create(lua_State* L);
FDT* FDT_create(lua_State* L);

#endif
