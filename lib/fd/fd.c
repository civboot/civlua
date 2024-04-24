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
#include <poll.h>
#include <sys/stat.h>


#include "fd.h"

#define FD_EOF     (-1)
#define FD_RUNNING (-2)
#define LEN(FD)  ((FD)->ei - (FD)->si)

#if __APPLE__
#include <crt_externs.h>
#define environ (*_NSGetEnviron())
#include <dispatch/dispatch.h>
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

// ----------------------
// -- FD CREATE / CLOSE
static void FD_freebuf(FD* fd);

// Create a FD object
static void FD_init(FD* fd) {
  fd->code = 0; fd->fileno = -1; fd->pos = 0;
  fd->size = 0; fd->si = 0; fd->ei = 0;
  fd->buf = NULL;
}
FD* FD_create(LS* L) {
  FD* fd = (FD*)lua_newuserdata(L, sizeof(FD));
  FD_init(fd);
  luaL_setmetatable(L, LUA_FD);
  return fd;
}

void FD_close(FD* fd) {
  if(fd->fileno >= 0) { 
    printf("!! closing fd %i\n", fd->fileno);
    close(fd->fileno); fd->fileno = -1; }
  FD_freebuf(fd);
  fd->code = 0;
}

// ----------------------
// -- FDT CREATE / CLOSE
static void* FDT_run(void* d) {
  FDT* fdt = (FDT*) d;
  while(true) {
    if(sem_wait(&fdt->sem)) break;
    printf("!! FDT_run awoken code=%i\n", fdt->fd.code);
    if(fdt->stopped)        break;
    fdt->meth(&fdt->fd);
  }
  fdt->stopped = 2;
  return NULL;
}

FDT* FDT_create(LS* L) {
  FDT* fdt = (FDT*)lua_newuserdata(L, sizeof(FDT));
  FD_init(&fdt->fd); fdt->meth = NULL; fdt->stopped = false;
  luaL_setmetatable(L, LUA_FDT);
  if(sem_init(&fdt->sem, 0, 0)) goto error;
  else if (pthread_create(&fdt->th, NULL, FDT_run, (void*)fdt)) {
    sem_destroy(&fdt->sem);     goto error;
  }
  return fdt;
error:
  fdt->stopped = 3; fdt->fd.code = errno;
  return fdt;
}

// ----------------------
// -- FD ALLOCATE / DESTROY
// These methods are the logic used for both the threaded
// and non-threaded implementaiton of filedescriptors.
#define IO_SIZE   16384

// free/destroy
static void FD_freebuf(FD* fd) {
  if(fd->size) {
    // ensure pos reflects user state
    if(fd->ei - fd->si) lseek(fd->fileno, fd->pos, SEEK_SET);
    free((void*)fd->buf); fd->size = 0;
  }
  fd->buf = NULL; fd->si = 0; fd->ei = 0;
}

static void FD_realloc(FD* fd, int size) {
  if(size < IO_SIZE) size = IO_SIZE;
  if(fd->size == 0) fd->buf = NULL;
  char* buf = realloc((void*)fd->buf, size);
  if(!buf) return;
  fd->buf = buf; fd->size = size;
}

// ----------------------
// -- METHODS
// FD calls these semi-directly. FDT calls them through
// the thread.

// open buf, flags=ctrl
static void FD_open(FD* fd) {
  fd->fileno = open((char*)fd->buf, fd->ctrl, 0666);
  int code = 0, pos = 0;
  if(fd->fileno >= 0) {
    if(fd->ctrl & O_APPEND) {
      pos = lseek(fd->fileno, 0, SEEK_END);
      if(pos < 0) { pos = 0; code = errno; }
    }
  } else code = errno;
  fd->pos  = pos; fd->code = code;
}

static void FD_tmp(FD* fd) {
  FILE* f = tmpfile();         if(!f)             goto error;
  fd->fileno = dup(fileno(f)); if(fd->fileno < 0) goto error;
  fclose(f); fd->code = 0;
  return;
error:
  if(f) fclose(f);
  fd->code = errno;
}


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
  if(fd->ei - fd->si > 0) {
    memmove((char*)fd->buf, (char*)fd->buf + fd->si, fd->ei - fd->si);
  }
  fd->ei -= fd->si; fd->si = 0;
}

// Read into buffer until EOF or error
// If ctrl < 0 then breaks at that negated character (i.e. '\n').
// if ctrl > 0 then stops reading when that amount is read
static void FD_read(FD* fd) {
  if(fd->size) FD_shift(fd);
  else         FD_realloc(fd, IO_SIZE);
  if(!fd->buf) { fd->code = errno; return; }
  int ctrl = fd->ctrl, code = 0;
  while(true) {
    if((ctrl > 0) && ((fd->ei - fd->si) > ctrl)) break;
    if(fd->size - fd->ei == 0) FD_realloc(fd, fd->size * 2);
    if(!fd->buf) { code = errno; break; }
    printf("!! FD_read reading...\n");
    int rem = fd->size - fd->ei;
    int c = read(fd->fileno, (char*)fd->buf + fd->ei, rem);
    printf("!! FD_read loop code=%i c=%i ei=%i\n", fd->code, c, fd->ei);
    if(c < 0) { code = errno;  break; }
    fd->ei += c;
    if(ctrl < 0) {
      int i = FD_findc(fd, fd->ei - c, (char) -ctrl);
      if(i < fd->ei) break;
    }
    if(c < rem) { code = FD_EOF; break; } // EOF: signal to findc callers
  }
  printf("!! FD_read done code=%i len=%i\n", code, LEN(fd));
  fd->code = code;
}

// Write the contents of fd buf[si:ei)
//
// Note: size is unused and is typically zero to indicate
//   that buf is Lua owned.
static void FD_write(FD* fd) {
  int c = write(fd->fileno, (char*)fd->buf + fd->si, LEN(fd));
  if(c >= 0) { fd->si += c; fd->pos += c; fd->code = 0; }
  else         fd->code = errno;
}

// attempt to seek using only buffer, else update FD.
// return true if complete (no syscall needed)
static bool FD_seekpre(FD* fd, off_t offset, int whence) {
  printf("!! SEEK=%u set=%u cur=%u end=%u\n", whence, SEEK_SET, SEEK_CUR, SEEK_END);
  off_t want = offset; switch(whence) {
    case SEEK_CUR: want += fd->pos; // make absolute
    case SEEK_SET:
      printf("!! seekpre %u offset=%u want/pos=%u/%u\n", whence, offset, want, fd->pos);
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
  ASSERT(L, fd->code >= FD_EOF, "%s while not ready", name);
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
  ASSERT(L, fd->buf, "no buffer");
  printf("!! pop %i %i %i\n", fd->si, fd->ei, till);
  printf("!! pop.buf='%.*s'\n", LEN(fd), (char*)fd->buf + fd->si);
  if(till == 0) till = fd->ei;
  else if(till < 0) {
    till = FD_findc(fd, fd->si, (char)(-till));
    if(till >= fd->ei) return 0; // nil (not found)
    till++; // include character in found
  } else {
    till += fd->si;
    if(till > fd->ei) return 0; // nil (not enough bytes)
  }
  if(till  == fd->si) return 0; // nil instead of empty
  lua_pushlstring(L, (char*)fd->buf + fd->si, till - fd->si);
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
  fd->buf = (char*)luaL_checklstring(L, 2, (size_t*)&fd->ei);
  return 0;
}

static int l_FD_codestr(LS* L) {
  int code = asfd(L)->code; char* str = "fd ready";
  if(code > 0)      str = strerror(code);
  else if(code < 0) str = "fd running";
  lua_pushstring(L, str); return 1;
}

// Note: written data is ALWAYS "flushed" if in the done state.
// From fflush(3):
//   For input streams associated with seekable files discards any buffered data
//   that has been fetched from the underlying file
static int l_FD_flush(LS* L) {
  FD* fd = asfd(L);
  if(fd->size> 0) return 0;
  struct stat sbuf = {0};
  if(fstat(fd->fileno, &sbuf)) { fd->code = errno; return 0; }
  if(sbuf.st_mode != S_IFREG) return 0;
  fd->pos += fd->ei - fd->si; // unpopped file pos
  fd->si = 0; fd->ei = 0;
  return 0;
}

#define FD_intfield(FIELD) \
  static int l_FD_##FIELD(LS* L) \
  { lua_pushinteger(L, asfd(L)->FIELD); return 1; } \

FD_intfield(code);
FD_intfield(fileno);
FD_intfield(pos);
FD_intfield(ctrl);

static int l_FD_setfileno(LS* L) {
  asfd(L)->fileno = luaL_checkinteger(L, 2); return 0;
}

// ----------------------
// -- FD LUA METHODS
#define toFD(L) ((FD*)luaL_checkudata(L, 1, LUA_FD))
#define toFDT(L) ((FDT*)luaL_checkudata(L, 1, LUA_FDT))
#define fdGetFD(V)  (V)
#define fdGetFDT(V) (&(V)->fd)

// (fd, till=0) -> (code)
// read from file into buf. The amount depends on `till`
// * zero: read till EOF
// * positive: read at least this amount of bytes
// * negative: read until the negated character
//
// Returns the code for convinience.
// Note: call l_FD_pop() for the read string.
#define PRE_READ(fd) \
  assertReady(L, fd, "read");           \
  (fd)->ctrl = luaL_optnumber(L, 2, 0); \
  (fd)->code = FD_RUNNING;
static int l_FD_read(LS* L) {
  FD* fd = toFD(L); PRE_READ(fd);
  FD_read(fd);
  lua_pushinteger(L, fd->code); return 1;
}
static int l_FDT_read(LS* L) {
  FDT* fdt = toFDT(L); PRE_READ(&fdt->fd);
  fdt->meth = FD_read; sem_post(&fdt->sem);
  lua_pushinteger(L, fdt->fd.code); 
  return 1;
}
#undef PRE_READ

// (fd, string) -> (code)
// Write a string. The code is returned for convienicence.
static int l_FD_write(LS* L) {
  FD* fd = toFD(L); fd->code = FD_RUNNING;
  FD_write(fd);
  lua_pushinteger(L, fd->code); return 1;
}
static int l_FDT_write(LS* L) {
  FDT* fdt = toFDT(L); fdt->fd.code = FD_RUNNING;
  fdt->meth = FD_write; sem_post(&fdt->sem);
  return 0;
}

// (fd, offset, whence) -> (code)
// Seek to offset+whence. The code is returned for convienicence.
#define IF_PRE_SEEK(fd) \
  assertReady(L, fd, "seek");             \
  off_t offset = luaL_checkinteger(L, 2); \
  int whence   = luaL_checkinteger(L, 3); \
  (fd)->code = FD_RUNNING; \
  if(FD_seekpre(fd, offset, whence)) (fd)->code = 0;

static int l_FD_seek(LS* L) {
  FD* fd = toFD(L);
  IF_PRE_SEEK(fd) else FD_seek(fd);
  lua_pushinteger(L, fd->code); return 1;
}
static int l_FDT_seek(LS* L) {
  FDT* fdt = toFDT(L); 
  IF_PRE_SEEK(&fdt->fd) else {
    fdt->meth = FD_seek; sem_post(&fdt->sem);
  }
  lua_pushinteger(L, fdt->fd.code); return 1;
}
#undef IF_PRE_SEEK

static int l_FD_create(LS* L)  { FD_create(L);  return 1; }
static int l_FDT_create(LS* L) { FDT_create(L); return 1; }

// open(path, flags) -> FD
static int l_FD_open(LS* L) {
  const char* path = luaL_checkstring(L, 1);
  const int flags = luaL_checkinteger(L, 2);
  FD* fd = FD_create(L);
  fd->buf = (char*)path; fd->ctrl = flags;
  fd->code = FD_RUNNING; FD_open(fd);
  return 1;
}
static int l_FDT_open(LS* L) {
  const char* path = luaL_checkstring(L, 1);
  const int flags = luaL_checkinteger(L, 2);
  FDT* fdt = FDT_create(L); FD* fd = &fdt->fd;
  fd->buf = (char*)path; fd->ctrl = flags;
  fd->code = FD_RUNNING;
  fdt->meth = FD_open; sem_post(&fdt->sem);
  return 1;
}

static int l_FD_tmp(LS* L) {
  FD* fd = FD_create(L);
  FD_tmp(fd);
  return 1;
}
static int l_FDT_tmp(LS* L) {
  FDT* fdt = FDT_create(L); FD* fd = &fdt->fd;
  fdt->meth = FD_tmp; sem_post(&fdt->sem);
  return 1;
}
#undef FD_TMP

static int l_FD_close(LS* L) {
  FD_close(toFD(L));
  return 0;
}
static int l_FDT_close(LS* L) {
  FDT* fdt = toFDT(L); assertReady(L, &fdt->fd, "close");
  fdt->fd.code = FD_RUNNING;
  fdt->meth = FD_close; sem_post(&fdt->sem);
  return 0;
}
void FDT_destroy(FDT* fdt) {
  if(!fdt->stopped) {
    fdt->stopped = 1;
    sem_post(&fdt->sem); pthread_join(fdt->th, NULL);
    sem_post(&fdt->sem); // fails on mac without this
    sem_destroy(&fdt->sem);
  }
  FD_close(&fdt->fd);
}
static int l_FDT_destroy(LS* L) { FDT_destroy(toFDT(L)); }

// (fd) -> code, flags
static int l_FD_getflags(LS* L) {
  FD* fd = asfd(L);
  int fl = fcntl(fd->fileno, F_GETFL);
  fd->code = (fl < 0) ? errno : 0;
  lua_pushinteger(L, fd->code);
  lua_pushinteger(L, fl);
  return 2;
}

// (fd, flags) -> code
static int l_FD_setflags(LS* L) {
  FD* fd = asfd(L); fd->code = FD_RUNNING;
  int fl = fcntl(fd->fileno, F_SETFL, luaL_checkinteger(L, 2));
  fd->code = (fl < 0) ? errno : 0;
  lua_pushinteger(L, fd->code);
  return 1;
}

// ---------------------
// -- PollList
const char* LUA_PL = "fd.PollList";
#define toPL(L) \
  ((PL *)luaL_checkudata(L, 1, LUA_PL))

typedef struct _PL {
  int size;
  struct pollfd* fds;
} PL;

static void PL_realloc(LS* L, PL* pl, int size) {
  struct pollfd* fds = realloc(pl->fds, size);
  ASSERT(L, fds, "OOM: realloc pollfds size=%I", size);
  for(int i=pl->size; i < size; i++) {
    fds[i].fd = -1; fds[i].revents = 0;
  }
  pl->fds = fds; pl->size = size;
}
static int l_PL_new(LS* L) {
  PL* pl = (PL*)lua_newuserdata(L, sizeof(PL));
  pl->size = 0; pl->fds = NULL;
  luaL_setmetatable(L, LUA_PL);
  return 1;
}
static int l_PL_resize(LS* L) {
  PL_realloc(L, toPL(L), luaL_checkinteger(L, 2)); return 0;
}
static int l_PL_destroy(LS* L) {
  PL* pl = toPL(L);
  if(pl->fds) { free(pl->fds); pl->size = 0; pl->fds = NULL; }
  return 0;
}
static int l_PL_size(LS* L) { lua_pushinteger(L, toPL(L)->size); return 1; }

// (pl, index, fileno, events)
// Note: indexes are 0-based
static int l_PL_set(LS* L) {
  PL* pl = toPL(L);
  int index  = luaL_checkinteger(L, 2);
  int fileno = luaL_checkinteger(L, 3);
  int events = luaL_checkinteger(L, 4);
  pl->fds[index].fd      = fileno;
  pl->fds[index].events  = events;
  pl->fds[index].revents = 0;
}

// (pl, timeoutMs) -> {filenos}
static int l_PL_ready(LS* L) {
  PL* pl = toPL(L);
  int timeoutMs = luaL_checkinteger(L, 2);
  int count = poll(pl->fds, pl->size, timeoutMs);
  lua_createtable(L, count, 0);
  int ti = 1;
  for(int i = 0; i < pl->size; i++) {
    if(pl->fds[i].revents) {
      lua_pushinteger(L, pl->fds[i].fd);
      lua_seti(L, -2, ti); ti++;
      pl->fds[i].revents = 0;
    }
  }
  return 1;
}

// ----------------------
// -- DEFINE LIBRARY

// (i) -> ~i: bitwise inversion of integer
static int l_inv(LS* L) {
  lua_pushinteger(L, ~luaL_checkinteger(L, 1));
  return 1;
}
static const struct luaL_Reg fd_sys[] = {
  {"openFD", l_FD_open},   {"openFDT", l_FDT_open},
  {"tmpFD",  l_FD_tmp},    {"tmpFDT",  l_FDT_tmp},
  {"newFD",  l_FD_create}, {"newFDT",  l_FDT_create},
  {"pollList", l_PL_new},
  {"inv", l_inv},
  {NULL, NULL},
};

#define L_setmethod(L, KEY, FN) \
  lua_pushcfunction(L, FN); lua_setfield(L, -2, KEY);

int luaopen_fd_sys(LS *L) {
  luaL_newlib(L, fd_sys);

    #define FD_METHODS  (/*native=*/ 11 + /*lua=*/ 3)
    luaL_newmetatable(L, LUA_FD);
      L_setmethod(L, "__gc", l_FD_close);
      lua_createtable(L, 0, FD_METHODS);
        // fields
        L_setmethod(L, "code",     l_FD_code);
        L_setmethod(L, "fileno",   l_FD_fileno);
        L_setmethod(L, "pos",      l_FD_pos);
        L_setmethod(L, "_setfileno", l_FD_setfileno);

        // true methods
        L_setmethod(L, "close",    l_FD_close);
        L_setmethod(L, "codestr",  l_FD_codestr);
        L_setmethod(L, "_writepre",l_FD_writepre);
        L_setmethod(L, "_write",   l_FD_write);
        L_setmethod(L, "_getflags",l_FD_getflags);
        L_setmethod(L, "_setflags",l_FD_setflags);
        L_setmethod(L, "_read",    l_FD_read);
        L_setmethod(L, "_seek",    l_FD_seek);
        L_setmethod(L, "_pop",     l_FD_pop);
        L_setmethod(L, "_flush",   l_FD_flush);
      lua_setfield(L, -2, "__index");
    lua_setfield(L, -2, "FD");

    luaL_newmetatable(L, LUA_FDT);
      L_setmethod(L, "__gc", l_FDT_destroy);
      lua_createtable(L, 0, FD_METHODS);
        // fields
        L_setmethod(L, "code",     l_FD_code);
        L_setmethod(L, "fileno",   l_FD_fileno);
        L_setmethod(L, "pos",      l_FD_pos);
        L_setmethod(L, "_setfileno", l_FD_setfileno);

        // true methods
        L_setmethod(L, "_close",   l_FDT_close);
        L_setmethod(L, "codestr",  l_FD_codestr);
        L_setmethod(L, "_writepre",l_FD_writepre);
        L_setmethod(L, "_write",   l_FDT_write);
        L_setmethod(L, "_getflags",l_FD_getflags);
        L_setmethod(L, "_setflags",l_FD_setflags);
        L_setmethod(L, "_read",    l_FDT_read);
        L_setmethod(L, "_seek",    l_FDT_seek);
        L_setmethod(L, "_pop",     l_FD_pop);
        L_setmethod(L, "_flush",   l_FD_flush);
      lua_setfield(L, -2, "__index");
    lua_setfield(L, -2, "FDT");

  luaL_newmetatable(L, LUA_PL);
    L_setmethod(L, "__gc", l_PL_destroy);
    lua_createtable(L, 0, 4); // __index table
      L_setmethod(L, "size",    l_PL_size);
      L_setmethod(L, "resize",  l_PL_resize);
      L_setmethod(L, "set",     l_PL_set);
      L_setmethod(L, "ready",   l_PL_ready);
    lua_setfield(L, -2, "__index");
    lua_setfield(L, -2, "PL");

  #define setconstfield(L, CONST) \
    lua_pushinteger(L, CONST); lua_setfield(L, -2, #CONST)
  setconstfield(L, FD_EOF);  setconstfield(L, FD_RUNNING);

  // open constants
  setconstfield(L, O_RDONLY); setconstfield(L, O_WRONLY);
  setconstfield(L, O_RDWR);   setconstfield(L, O_APPEND);
  setconstfield(L, O_CREAT);  setconstfield(L, O_TRUNC);
  setconstfield(L, O_NONBLOCK);

  // seek constants
  setconstfield(L, SEEK_SET); setconstfield(L, SEEK_CUR);
  setconstfield(L, SEEK_END);

  // poll constants
  setconstfield(L, POLLIN);   setconstfield(L, POLLOUT);

  // important errors
  setconstfield(L, EWOULDBLOCK); setconstfield(L, EAGAIN);

  // std descriptors
  setconstfield(L, STDIN_FILENO); setconstfield(L, STDOUT_FILENO);
  setconstfield(L, STDERR_FILENO);

  return 1;
}