#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <stdbool.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include <unistd.h>
#include <pthread.h>
#include <fcntl.h>
#include <assert.h>

#include "fd.h"

#define FD_RUNNING (-1)
#define LEN(FD)  ((FD)->ei - (FD)->si)

#if __APPLE__
#include <crt_externs.h>
#define environ (*_NSGetEnviron())

#include <dispatch/dispatch.h>
typedef dispatch_semaphore_t sem_t;
static int sem_init(sem_t* sem, int _unused, int count) {
  *sem = dispatch_semaphore_create(count);
  return (*sem == NULL) ? -1 : 0;
}
static int sem_wait(sem_t* sem) {
  return dispatch_semaphore_wait(*sem, DISPATCH_TIME_FOREVER);
}
static int sem_post(sem_t* sem) {
  dispatch_semaphore_signal(*sem); return 0;
}
static int sem_destroy(sem_t* sem) {
  dispatch_release(*sem); return 0;
}
#else
#include <semaphore.h>
#endif

typedef lua_State LS;

#define ASSERT(L, OK, ...) \
  if(!(OK)) { luaL_error(L, __VA_ARGS__); }

// Create a FD object
FD* FD_create(LS* L) {
  FD* fd = (FD*)lua_newuserdata(L, sizeof(FD));
  // note: ctrl+code not set
  fd->fileno = -1; fd->pos = 0;
  fd->size = 0; fd->si = 0; fd->ei = 0;
  fd->buf = NULL; 
  luaL_setmetatable(L, LUA_FD);
  return fd;
}

static void FD_freebuf(FD* fd);
static void FD_close(FD* fd) {
  if(fd->fileno >= 0) { close(fd->fileno); fd->fileno = -1; }
  FD_freebuf(fd);
}

// ----------------------
// -- FD ALLOCATE / DESTROY
// These methods are the logic used for both the threaded
// and non-threaded implementaiton of filedescriptors.
#define IO_SIZE   16384

// free/destroy
static void FD_freebuf(FD* fd) {
  if(fd->size) {
    fd->pos += fd->ei - fd->si; // unpopped file pos
    free(fd->buf); fd->size = 0;
  }
  fd->buf = NULL; fd->si = 0; fd->ei = 0;
}

static void FD_realloc(LS* L, FD* fd, int size) {
  if(size < IO_SIZE) size = IO_SIZE;
  if(fd->size == 0) fd->buf = NULL;
  printf("!! FD_realloc %u\n", size);
  char* buf = realloc(fd->buf, size);
  ASSERT(L, buf, "OOM: realloc fd size=%I", size);
  fd->buf = buf; fd->size = size;
}

// ----------------------
// -- READ / WRITE / SEEK
// FD calls these semi-directly. FDT calls them through
// the thread.

// find character index. If index==ei then not found.
static size_t FD_findc(FD* fd, size_t si, char c) {
  for(; si < fd->ei; si++) {
    if(c == fd->buf[si]) break;
  }
  return si;
}

// shift the buffer left, typically done before a
// read operation.
static void FD_shift(FD* fd) {
  if(fd->si == 0) return;
  memmove(fd->buf, fd->buf + fd->si, fd->ei - fd->si);
  fd->ei -= fd->si; fd->si = 0;
}

// Read into buffer until EOF or error
// If ctrl < 0 then breaks at that negated character (i.e. '\n').
// if ctrl > 0 then stops reading when that amount is read
static void FD_read(LS* L, FD* fd) {
  if(fd->size) FD_shift(fd);
  else         FD_realloc(L, fd, IO_SIZE);
  int ctrl = fd->ctrl, code = 0;
  while(true) {
    if((ctrl > 0) && ((fd->ei - fd->si) > ctrl)) break;
    if(fd->size - fd->ei == 0) FD_realloc(L, fd, fd->size * 2);
    int c = read(fd->fileno, fd->buf + fd->ei, fd->size - fd->ei);
    if(c >= 0) { fd->ei += c; }
    else         code = errno;
    if(c <= 0) break;
    if(ctrl < 0) {
      int i = FD_findc(fd, fd->ei - c, (char) -ctrl);
      if(i < fd->ei) break;
    }
  }
  fd->code = code;
}

// Write the contents of fd buf[si:ei)
//
// Note: size is unused and is typically zero to indicate
//   that buf is Lua owned.
static void FD_write(FD* fd) {
  int c = write(fd->fileno, fd->buf + fd->si, LEN(fd));
  if(c >= 0) { fd->si += c; fd->pos += c; fd->code = 0; }
  else         fd->code = errno;
}

// attempt to seek using only buffer, else update FD.
// return true if complete (no syscall needed)
static bool FD_seekpre(FD* fd, off_t offset, int whence) {
  off_t want = offset; switch(whence) {
    case SEEK_CUR: want += fd->pos; // make absolute
    case SEEK_SET:
      if((fd->pos <= want) && (want <= fd->pos + LEN(fd))) {
        fd->si += want - fd->pos; fd->pos = want;
        return true;
      } // fallthrough
    case SEEK_END: break; // rely on syscall
    default: assert(false);
  }
  fd->pos = offset; fd->ctrl = whence;
  return false;
}

static void FD_seek(FD* fd) {
  off_t pos = lseek(fd->fileno, fd->pos, fd->ctrl);
  if(pos == -1) { fd->code = errno; return; }
  fd->pos = pos;
  if(fd->size) { fd->si = 0; fd->ei = 0; } // read buffer only
  fd->code = 0;
}

// ----------------------
// -- FD/T LUA METHODS
// These are used by both FD and FDT

static FD* asfd(LS* L) {
  FD* fd = luaL_testudata(L, 1, LUA_FD);  if(fd) return fd;
      fd = luaL_testudata(L, 1, LUA_FDT); if(fd) return fd;
  luaL_error(L, "arg 1 not FD or FDT");
}

static void assertReady(LS* L, FD* fd, const char* name) {
  ASSERT(L, fd->code >= 0, "%s while not ready", name);
}

static int l_FD_close(LS* L) {
  FD_close((FD*)luaL_checkudata(L, 1, LUA_FD));
  return 0;
}

// (fd, till=-1) -> string
//
// pop a string from the buffer. till can be:
//
// * zero: pop whole buffer
// * negative: pop the buffer until that character.
//     Return nil character not found.
// * positive: pop exactly that many characters or nil.
//
// note: returns nil instead of an empty string
static int l_FD_pop(LS* L) {
  FD* fd = asfd(L); assertReady(L, fd, "pop");
  int till = luaL_optnumber(L, 2, 0);
  if(till == 0) till = fd->ei;
  else if(till < 0) {
    till = FD_findc(fd, fd->si, (char)(-till));
    if(till >= fd->ei) return 0; // nil (not found)
  } else {
    till += fd->si;
    if(till > fd->ei) return 0; // nil (not enough bytes)
  }
  if(till  == fd->si) return 0; // nil instead of empty
  lua_pushlstring(L, fd->buf + fd->si, till);
  fd->pos += till - fd->si;
  fd->si = till;
  return 1;
}

// (fd, string) -> ()
// Update the buffer to prepare for string writing.
//
// Note: This does NOT write the string.
// Reason: l_FD_write may need to be called multiple times if EAGAIN is the
//   result.
// Warning: it is your job to ensure the string doesn't go out of scope while
//   the FD is using it.
static int l_FD_writepre(LS* L) {
  FD* fd = asfd(L); assertReady(L, fd, "write");
  FD_freebuf(fd);
  fd->buf = (char*)luaL_checklstring(L, 2, &fd->ei);
  return 0;
}

static int l_FD_codestr(LS* L) {
  int code = asfd(L)->code; char* str = "fd ready";
  if(code > 0)      str = strerror(code);
  else if(code < 0) str = "fd running";
  lua_pushstring(L, str); return 1;
}

#define FD_intfield(FIELD) \
  static int l_FD_##FIELD(LS* L) \
  { lua_pushinteger(L, asfd(L)->FIELD); return 1; }

FD_intfield(code);
FD_intfield(fileno);
FD_intfield(pos);

// ----------------------
// -- FD LUA METHODS

#define tofd(L) ((FD*)luaL_checkudata(L, 1, LUA_FD))

// (fd, till=0) -> (code)
// read from file into buf. The amount depends on `till`
// * zero: read till EOF
// * positive: read at least this amount of bytes
// * negative: read until the negated character
//
// Returns the code for convinience.
// Note: call l_FD_pop() for the read string.
static int l_FD_read(LS* L) {
  FD* fd = tofd(L); assertReady(L, fd, "read");
  fd->ctrl = luaL_optnumber(L, 2, 0);
  fd->code = FD_RUNNING; FD_read(L, fd);
  lua_pushinteger(L, fd->code); return 1;
}

// (fd, string) -> (code)
// Write a string. The code is returned for convienicence.
static int l_FD_write(LS* L) {
  FD* fd = tofd(L);
  fd->code = FD_RUNNING; FD_write(fd);
  lua_pushinteger(L, fd->code); return 1;
}

// (fd, offset, whence) -> (code)
// Seek to offset+whence. The code is returned for convienicence.
static int l_FD_seek(LS* L) {
  FD* fd = tofd(L); assertReady(L, fd, "seek");
  off_t offset = luaL_checkinteger(L, 2);
  int whence   = luaL_checkinteger(L, 3);
  if(FD_seekpre(fd, offset, whence)) fd->code = 0;
  else { fd->code = FD_RUNNING; FD_seek(fd); }
  lua_pushinteger(L, fd->code); return 1;
}

// (path, flags) -> FD, errno
static int l_FD_open(LS* L) {
  const char* path = luaL_checkstring(L, 1);
  const int flags = luaL_checkinteger(L, 2);
  FD* fd = FD_create(L);
  fd->fileno = open(path, flags, 0666);
  if(fd->fileno >= 0) {
    fd->code = 0;
    if(flags & O_APPEND) {
      fd->pos = lseek(fd->fileno, 0, SEEK_END);
      if(fd->pos < 0) fd->code = errno;
    } else fd->pos = 0;
  } else fd->code = errno;
  return 1;
}

// ----------------------
// -- DEFINE LIBRARY

static const struct luaL_Reg fd_sys[] = {
  {"openFD", l_FD_open},
  {NULL, NULL},
};

#define L_setmethod(L, KEY, FN) \
  lua_pushcfunction(L, FN); lua_setfield(L, -2, KEY);

int luaopen_fd_sys(LS *L) {
  printf("!! opening fd.c\n");
  luaL_newlib(L, fd_sys);

    luaL_newmetatable(L, LUA_FD);
      L_setmethod(L, "__gc", l_FD_close);
      lua_createtable(L, 0, 5);
        // fields
        L_setmethod(L, "code",     l_FD_code);
        L_setmethod(L, "fileno",   l_FD_fileno);
        L_setmethod(L, "pos",      l_FD_pos);

        // true methods
        L_setmethod(L, "close",    l_FD_close);
        L_setmethod(L, "codestr",  l_FD_codestr);
        L_setmethod(L, "_writepre",l_FD_writepre);
        L_setmethod(L, "_write",   l_FD_write);
        L_setmethod(L, "_read",    l_FD_read);
        L_setmethod(L, "_seek",    l_FD_seek);
        L_setmethod(L, "_pop",     l_FD_pop);

      lua_setfield(L, -2, "__index");

    lua_setfield(L, -2, "FD");

  #define setconstfield(L, CONST) \
    lua_pushinteger(L, CONST); lua_setfield(L, -2, #CONST)
  setconstfield(L, FD_RUNNING);

  // open constants
  setconstfield(L, O_RDONLY); setconstfield(L, O_WRONLY);
  setconstfield(L, O_RDWR);   setconstfield(L, O_APPEND);
  setconstfield(L, O_CREAT);  setconstfield(L, O_TRUNC);
  setconstfield(L, O_NONBLOCK);

  // seek constants
  setconstfield(L, SEEK_SET); setconstfield(L, SEEK_CUR);
  setconstfield(L, SEEK_END);

  // important errors
  setconstfield(L, EWOULDBLOCK); setconstfield(L, EAGAIN);

  return 1;
}
