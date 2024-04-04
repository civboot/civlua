#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <stdbool.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include <time.h>
#include <dirent.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#include <signal.h>
#include <pthread.h>
#include <fcntl.h>

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

// ---------------------
// -- Utilities
typedef lua_State LS;
#define l_intdefault(L, I, DEFAULT) \
  (lua_isnoneornil(L, I) ? DEFAULT : luaL_checkinteger(L, I))


#define ASSERT(L, OK, ...) \
  if(!(OK)) { luaL_error(L, __VA_ARGS__); }
#define SERR strerror(errno)

#define L_setmethod(L, KEY, FN) \
  lua_pushcfunction(L, FN); lua_setfield(L, -2, KEY);


// Return a string array with null-terminated end.
// Note: you MUST free it.
char** checkstringarray(LS *L, int index, int* lenOut) {
  lua_len(L, index); int len = luaL_checkinteger(L, -1); lua_pop(L, 1);
  char** arr = malloc(sizeof(char*) * (len + 1));
  for(int i = 0; i < len; i++) {
    lua_geti(L, index, i + 1); arr[i] = (char*)luaL_checkstring(L, -1);
    lua_pop(L, 1);
  }
  arr[len] = NULL; *lenOut = len;
  return arr;
}

static int l_strerrno(LS* L) {
  lua_pushstring(L, strerror(luaL_checkinteger(L, 1))); return 1;
}

// ---------------------
// -- File Utilities
// For some reason these are not exported (???)
// https://www.lua.org/source/5.2/liolib.c.html
#ifndef LUA_FILEHANDLE
#define LUA_FILEHANDLE "FILE*"
#endif
typedef luaL_Stream LStream;
#define tolstream(L)    ((LStream *)luaL_checkudata(L, 1, LUA_FILEHANDLE))
static int LStream_close(LStream* p) {
  int res = 0; if(p->f) { 
    res = fclose(p->f); p->f = NULL; p->closef = NULL;
  }
  return res;
}
static int l_fclose(LS *L) {
  return luaL_fileresult(L, (LStream_close(tolstream(L)) == 0), NULL);
}
static LStream *newprefile (LS *L) {
  LStream *p = (LStream *)lua_newuserdata(L, sizeof(LStream));
  p->closef = NULL;  // mark file handle as 'closed'
  luaL_setmetatable(L, LUA_FILEHANDLE);
  return p;
}
static void initfile(LStream* ls, FILE* f) {
  ls->f = f; ls->closef = &l_fclose;
}

// ---------------------
// -- Time
int gettime(LS *L, clockid_t clk_id) {
  struct timespec spec = {};
  clock_gettime(clk_id, &spec);
  lua_pushinteger(L, spec.tv_sec);
  lua_pushinteger(L, spec.tv_nsec);
  return 2;
} int l_epoch(LS *L) { return gettime(L, CLOCK_REALTIME);  }
  int l_mono(LS *L)  { return gettime(L, CLOCK_MONOTONIC); }

int l_nanosleep(LS*L) {
  struct timespec req, rem;
  req.tv_sec  = luaL_checkinteger(L, 1); req.tv_nsec = luaL_checkinteger(L, 2);
  while(nanosleep(&req, &rem)) req = rem;
  return 0;
}

// ---------------------
// -- Dir iterator and other functions

// mkdir(path, mode=0777) -> ok, errno
//   note: 0777 is octal.
int l_mkdir(LS* L) {
  const char* path = luaL_checkstring(L, 1);
  mode_t mode = l_intdefault(L, 2, 0777);
  if(mkdir(path, mode)) {
    lua_pushnil(L); lua_pushinteger(L, errno); return 2;
  }
  lua_pushboolean(L, true); return 1;
}

static int rmfn(LS* L, char* name, int fn(const char*)) {
  const char* path = luaL_checkstring(L, 1);
  bool rerr = lua_toboolean(L, 2);
  if(!fn(path)) return 0;
  ASSERT(L, rerr, "failed to %s: %s (%s)", name, path, SERR);
  lua_pushinteger(L, errno); return 1;
}
// rm(path, reterrno) -> errno: removes path
// if reterrno just returns errno on failure, else fails
static int l_rm(LS* L)    { return rmfn(L, "rm",    unlink); }
static int l_rmdir(LS* L) { return rmfn(L, "rmdir", rmdir); }
static int l_rename(LS* L) { // rename(old, new, reterrno) -> errno
  const char* old = luaL_checkstring(L, 1);
  const char* new = luaL_checkstring(L, 2);
  bool rerr       = lua_toboolean(L, 3);
  if(!rename(old, new)) return 0;
  ASSERT(L, rerr, "failed to rename %s -> %s: %s", old, new, SERR);
  lua_pushinteger(L, errno); return 1;
}
static int l_exists(LS* L) {
  const char* path = luaL_checkstring(L, 1);
  lua_pushboolean(L, 0 == access(path, F_OK)); return 1;
}

const char* DIR_META = "civix.Dir";
#define toldir(L) (DIR**)luaL_checkudata(L, 1, DIR_META)

static void DIR_gc(DIR** dir) {
  if(*dir) { closedir(*dir); *dir = NULL; }
}
static int l_dir_gc(LS *L) {
  DIR_gc(toldir(L)); return 0;
}

// Each time called return next: (name, ftype) or nil
static int dir_iter(LS *L) {
	DIR** dir = (DIR**) luaL_checkudata(L, lua_upvalueindex(1), DIR_META);
  if(*dir == NULL) return 0; // already freed
  struct dirent* ent;
skip:
  if((ent = readdir(*dir)) == NULL) {
    DIR_gc(dir); return 0; // done, free *DIR immediately
  }
  if((0==strcmp(".", ent->d_name)) || (0==strcmp("..", ent->d_name)))
    { goto skip; }
  lua_pushstring(L, ent->d_name);
  switch(ent->d_type) {
#define DCASE(VAL, STR) case VAL: lua_pushstring(L, STR); break;
    DCASE(DT_BLK, "blk");   DCASE(DT_CHR, "chr");  DCASE(DT_DIR, "dir");
    DCASE(DT_FIFO, "fifo"); DCASE(DT_LNK, "link"); DCASE(DT_REG, "file");
    DCASE(DT_SOCK, "sock"); DCASE(DT_UNKNOWN, "unknown");
#undef DCASE
    default:         lua_pushnil(L);
  }
  return 2;
}

// return (name, ftype) iterator. Skips "." and ".."
static int l_dir(LS *L) {
  const char* path = luaL_checkstring(L, 1);
  printf("!! dir %s\n", path);
  DIR** dir = (DIR**)lua_newuserdata(L, sizeof(DIR*)); // stack: dir
  luaL_setmetatable(L, DIR_META);
  ASSERT(L, *dir = opendir(path), "cannot open %s: %s", path, SERR);
  lua_pushcclosure(L, dir_iter, 1);                    // stack: (empty)
  return 1;
}

// pathstat(path) -> st_mode
// * st_mode: see consts.S_*
static int l_pathstat(LS *L) {
  struct stat sbuf = {0};
  const char* path = luaL_checkstring(L, 1);
  ASSERT(L, stat(path, &sbuf) == 0, "cannot stat %s: %s", path, SERR);
  lua_pushinteger(L, sbuf.st_mode);
  return 1;
}

// ---------------------
// -- Shell
#define IO_SIZE  (0x4000)
#define wouldblock()  ((errno == EAGAIN) || (errno == EWOULDBLOCK))

const char* SH_META  = "civix.Sh";
const char* FD_META  = "civix.Fd";

#define tolfd(L) ((int*)luaL_checkudata(L, 1, FD_META))
static int* newfd(LS *L, int fileno) {
  int* fd = (int*)lua_newuserdata(L, sizeof(int));
  *fd = fileno; luaL_setmetatable(L, FD_META);
  return fd;
}
// open(path, flags)
static int l_fdopen(LS *L) {
  const char* path = luaL_checkstring(L, 1);
  int flags = luaL_checkinteger(L, 2);
  int fno = open(path, luaL_checkinteger(L, 2));
  ASSERT(L, fno >= 0, "failed to open %s: %s", path, SERR);
  newfd(L, fno); return 1;
}
static void fdclose(int* fd) {
  if(*fd >= 0) { close(*fd); *fd = -1; }
}
static int l_fdclose(LS *L) { fdclose(tolfd(L)); return 0; }
static LStream* fdtofile(LS *L, int* fd, const char* mode) {
  FILE* f = fdopen(*fd, mode);
  ASSERT(L, f, "failed to open fd=%I mode=%s: %s", *fd, mode, SERR);
  LStream* s = newprefile(L); initfile(s, f); *fd = -1;
  return s;
}
static int l_fdtofile(LS *L) {
  fdtofile(L, tolfd(L), luaL_checkstring(L, 2));
  return 1;
}

// fdread(fd, len) -> (out, error)
// only one of (out, error) can be set. Both are nil if WOULDBLOCK
static int l_fdread(LS *L) {
  int* fd = tolfd(L); ASSERT(L, *fd >= 0, "cannot read closed fd");
  int size = lua_isnoneornil(L, 2) ? IO_SIZE : luaL_checkinteger(L, 2);
  ASSERT(L, size <= IO_SIZE, "size > IO_SIZE");
  char buf[IO_SIZE];
  ssize_t c = read(*fd, buf, size); if(c < 0) {
    if(wouldblock()) return 0; // {nil} aka no result or err
    lua_pushnil(L);
    lua_pushstring(L, SERR);
    return 2;
  }
  lua_pushlstring(L, buf, c); return 1;
}

// write(s, start) -> {pos, error}; EWOULDBLOCK == {}
// pos is nil on error
// pos and error are nil on EWOULDBLOCK
// if pos < start it is an EOF
static int l_fdwrite(LS *L) {
  int* fd = tolfd(L); ASSERT(L, *fd >= 0, "cannot write to closed fd");
  size_t len; const char* s = luaL_checklstring(L, 2, &len);
  int start = lua_isnoneornil(L, 3) ? 0 : (luaL_checkinteger(L, 3) - 1);
  ASSERT(L, start >= 0,  "start must be >= 1");
  ASSERT(L, start < len, "start must be < len");

  ssize_t c = write(*fd, s + start, len - start); if(c < 0) {
    if(wouldblock()) return 0;
    lua_pushnil(L);
    lua_pushstring(L, SERR);
    return 2;
  }
  lua_pushinteger(L, start + c); return 1;
}

// retrieve the file descriptors fileno number.
static int l_fdfileno(LS *L) {
  int* fd = tolfd(L); if(*fd < 0) return 0; // nil
  lua_pushinteger(L, *fd);
  return 1;
}

// fdsetblocking(fd, isBlocking) to enable/disable blocking
static int l_fdsetblocking(LS *L) {
  int* fd = tolfd(L); ASSERT(L, *fd >= 0, "setblocking on closed fd");
  int flags = fcntl(*fd, F_GETFL);
  ASSERT(L, flags != -1, "fctl failed on fd %I: %s", *fd, SERR);
  if(lua_toboolean(L, 2)) flags &= ~O_NONBLOCK;
  else                    flags |=  O_NONBLOCK;
  fcntl(*fd, F_SETFL, flags);
  return 0;
}

// filenostat(fileno) -> st_mode
// See pathstat for constants.
static int l_filenostat(LS *L) {
  int fd = luaL_checkinteger(L, 1); struct stat sbuf = {0};
  ASSERT(L, fstat(fd, &sbuf) == 0, "fstat failed: %s", SERR);
  lua_pushinteger(L, sbuf.st_mode);
  return 1;
}

struct sh {
  pid_t pid; char** env; // note: env only set if needs freeing
  int rc;
};
#define tolsh(L) ((struct sh*)luaL_checkudata(L, 1, SH_META))
struct sh* sh_wait(struct sh* sh, int flags) {
  printf("!! sh_wait %i rc=%i\n", sh->pid, sh->rc);
  if(sh->pid) {
    siginfo_t infop = {0};
    if(waitid(P_PID, sh->pid, &infop, WEXITED | flags)) {
      fprintf(stderr, "ERROR: waitid failed\n");
      return sh;
    }
    if(infop.si_pid == sh->pid) { sh->pid = 0; sh->rc = infop.si_status; }
  }
  printf("!!  sh end %i rc=%i\n", sh->pid, sh->rc);
  return sh;
}

static void sh_gc(struct sh* sh) {
  if(sh->pid) { kill(sh->pid, SIGKILL); sh_wait(sh, 0); }
  if(sh->env) { free(sh->env); sh->env = NULL; }
}
static int l_sh_gc(LS *L) { sh_gc(tolsh(L)); return 0; }

// () -> isDone: asynchronously determine whether Sh is done.
static int l_sh_isDone(LS *L) {
  lua_pushboolean(L, sh_wait(tolsh(L), WNOHANG)->pid);
  return 1;
}

static int l_sh_rc(LS *L) {
  lua_pushinteger(L, tolsh(L)->rc);
  return 1;
}

// () -> : block until Sh is done.
static int l_sh_wait(LS *L) { sh_wait(tolsh(L), 0); return 0; }

static int l_sh(LS *L) {
  char **argv = NULL, **env = NULL; int _len; lua_settop(L, 3);
  const char* command = luaL_checkstring(L, 1);
  if(!lua_isnil(L, 2)) { argv = checkstringarray(L, 2, &_len); }
  if(!lua_isnil(L, 3)) { env = checkstringarray(L, 3, &_len); }

  struct sh* sh = (struct sh*)lua_newuserdata(L, sizeof(struct sh));
  luaL_setmetatable(L, SH_META);
  sh->pid = 0; sh->env = env;

  #define INIT_FD(NAME) NAME = newfd(L, fd); fd = 0;
  int fd = 0, ch_r = 0, ch_w = 0, ch_lw = 0;
  int *pr_r = NULL, *pr_w = NULL, *pr_lr = NULL;
  int rw[2]; char* err = "pipes";
  if(pipe(rw)) goto error; fd   = rw[0]; ch_w  = rw[1]; INIT_FD(pr_r);
  if(pipe(rw)) goto error; ch_r = rw[0]; fd    = rw[1]; INIT_FD(pr_w);
  if(pipe(rw)) goto error; fd   = rw[0]; ch_lw = rw[1]; INIT_FD(pr_lr);
  #undef INIT_FD

  int pid = fork(); if(pid == -1) goto error;
  else if(pid == 0) { // child
    fdclose(pr_r); fdclose(pr_w); fdclose(pr_lr);
    dup2(ch_w,  STDOUT_FILENO); close(ch_w);
    dup2(ch_lw, STDERR_FILENO); close(ch_lw);
    dup2(ch_r,  STDIN_FILENO);  close(ch_r);
    exit(100 + execvp(command, argv)); // note: exit should be unreachable
  } // else parent
  close(ch_w); close(ch_r); close(ch_lw);
  sh->pid = pid;
  return 4;
  error:
    if (fd) close(fd);
    if (ch_w) close(ch_w); if (ch_r) close(ch_r); if (ch_lw) close(ch_lw);
    luaL_error(L, "failed sh (%s): %s", err, SERR); return 0;
}

// ---------------------
// -- fdth: file descriptor backed by thread
// These file descriptor operations are run (blocking) on a separate pthread,
// making them non-blocking for Lua
#define FDTH_META "civix.fdth"
#define tolfdth(L)  ((struct fdth*)luaL_checkudata(L, 1, FDTH_META))

enum fdth_op {
  FD_DESTROYED, // destroyed, no further operation allowed
  FD_EXITED,    // exited, only destroy allowed
  FD_EXIT,      // tell thread to exit gracefully (to be joined)
  FD_READY, // the op is done, awaiting runop (sem_post(sem))
  FD_CLOSE, // close fd, sets fd=-1
  FD_OPEN,  // open(buf, flags=start), sets fd=fileno
  FD_SEEK,  // seek (offset=start, whence=end)
  // read/write: use buf/end to do standard read/write operation.
  //   thread updates start as data is read/written,
  //   so by end of read/write the value of start==end
  FD_READ, FD_WRITE,
  FD_INVALID,
};

struct fdth {
  enum fdth_op op; // see fdth_op
  pthread_t pthread; sem_t sem; int fd;
  int err;
  int start; int end; char buf[IO_SIZE];
};

void fdth_close(struct fdth* fdth) {
  if(fdth->fd < 0)         {}
  else if(close(fdth->fd)) fdth->err = errno;
  else                     fdth->fd = -1;
}

// Destroy fdth. This will BLOCK if fdth->op > FD_READY.
void fdth_destroy(struct fdth* fdth) {
  fprintf(stderr, "!!! destroying\n");
  if(fdth->op == FD_DESTROYED) return;
  fdth_close(fdth); while(fdth->op > FD_READY) {}
  fprintf(stderr, "!!!   joining\n");
  if(fdth->op > FD_EXIT) {
    fdth->op = FD_EXIT; sem_post(&fdth->sem);
  }
  pthread_join(fdth->pthread, NULL);
  fprintf(stderr, "!!!   sem_destroying\n");
  sem_post(&fdth->sem); // TODO: fails on mac without this, not sure why...
  sem_destroy(&fdth->sem);
  fdth->op = FD_DESTROYED;
}
int l_fdth_destroy(LS* L) { fdth_destroy(tolfdth(L));              return 0; }
int l_fdth_start(LS* L)   { lua_pushinteger(L, tolfdth(L)->start); return 1; }
int l_fdth_end(LS* L)     { lua_pushinteger(L, tolfdth(L)->end);   return 1; }
int l_fdth_fileno(LS* L)  { lua_pushinteger(L, tolfdth(L)->fd);    return 1; }
int l_fdth_error(LS* L) {
  int err = tolfdth(L)->err; if(!err) return 0;
  lua_pushstring(L, strerror(err));   return 1;
}
int l_fdth_isDone(LS* L)  {
  lua_pushboolean(L, tolfdth(L)->op <= FD_READY); return 1;
}
int l_fdth_isExited(LS* L) {
  lua_pushboolean(L, tolfdth(L)->op == FD_EXITED); return 1;
}

// fdth_buf(start=0, end=fdth->start) -> {bufStr}
//   Return the buf string from (default) [0, start)
//   Note: uses C-like indexes.
int l_fdth_buf(LS* L) {
  struct fdth* fdth = tolfdth(L);
  int start = lua_isnoneornil(L, 2) ? 0           : luaL_checkinteger(L, 2);
  int end   = lua_isnoneornil(L, 3) ? fdth->start : luaL_checkinteger(L, 3);
  ASSERT(L, (0 <= start) && (start < end), "invalid start: %I", start);
  ASSERT(L, (0 <= end) && (end < IO_SIZE), "invalid end: %I", end);
  lua_pushlstring(L, fdth->buf + start, (end - start));
  return 1;
}

void *fdth_start(void* inp) {
  struct fdth* fdth = (struct fdth*) inp;
  int c; char r = 'w';
  while(sem_wait(&fdth->sem) == 0) {
    fdth->err = 0;
    fprintf(stderr, "!!! running %X\n", fdth->op);
    switch(fdth->op) {
      case FD_DESTROYED:              return NULL; // invalid
      case FD_EXITED:  case FD_EXIT:  goto exit;
      case FD_INVALID: case FD_READY: break; // noop
      case FD_CLOSE:                  fdth_close(fdth); break;
      case FD_OPEN:
        fdth->fd = open(fdth->buf, fdth->start);
        if(fdth->fd < 0) { fdth->err = errno; }
        break;
      case FD_SEEK:
        fdth->start = lseek(fdth->fd, fdth->start, fdth->end);
        if(fdth->start < 0) fdth->err = errno;
        break;
      case FD_READ:
        c = read(fdth->fd, fdth->buf + fdth->start,
                               fdth->end - fdth->start);
        if(c >= 0) fdth->start += c; else fdth->err = errno;
        break;
      case FD_WRITE:
        c = write(fdth->fd, fdth->buf + fdth->start,
                                fdth->end - fdth->start);
        if(c >= 0) fdth->start += c; else fdth->err = errno;
        break;
    }
    fdth->op = FD_READY;
  }
exit:
  fdth->op = FD_EXITED;
  return NULL;
}

// create fdth, possibly already has fd set.
// On failure, errno will be set and eventfd set to less than 0.
void fdth_init(LS* L, struct fdth* fdth) {
  fdth->op = FD_READY;
  ASSERT(L, !sem_init(&fdth->sem, 0, 1),
         "failed to create semaphore: %s", SERR);
  fdth->err = pthread_create(&fdth->pthread, NULL, fdth_start, (void*)fdth);
  ASSERT(L, !fdth->err, "failed to create pthread: %s", SERR);
}

int l_fdth_create(LS* L) {
  int fd = lua_isnoneornil(L, 1) ? -1 : luaL_checkinteger(L, 1);
  struct fdth *fdth = (struct fdth*)lua_newuserdata(L, sizeof(struct fdth));
  fdth->fd = fd; fdth_init(L, fdth);
  luaL_setmetatable(L, FDTH_META);
  return 1;
}

// fdth_fill(fdth, str, start, end) -> ()
//   fill the buffer with str:sub(start, end)
//
// This sets buffer start=0, end=end-start
int l_fdth_fill(LS* L) {
  struct fdth* fdth = tolfdth(L);
  ASSERT(L, fdth->op == FD_READY, "fill when not ready");
  size_t blen; const char* str = luaL_checklstring(L, 2, &blen);
  int start = lua_isnoneornil(L, 3) ? 0    : (luaL_checkinteger(L, 3) - 1);
  int end   = lua_isnoneornil(L, 4) ? blen : (luaL_checkinteger(L, 4));
  ASSERT(L, start >= 0,  "invalid start index %I", start);
  ASSERT(L, end >= 0,    "invalid end index %I", end);
  ASSERT(L, end <= blen, "end > string length");
  ASSERT(L, (end - start) < IO_SIZE, "length too large");
  fdth->start = 0; fdth->end = (end - start);
  memmove(fdth->buf, str + start, fdth->end);
  fdth->buf[fdth->end] = 0;
  return 0;
}

// fdth_runop(fdth, op, start=nil, end=nil) -> ()
//   run an operation on fdth, first overriding start/end if set.
int l_fdth_runop(LS* L) {
  struct fdth* fdth = tolfdth(L);
  ASSERT(L, fdth->op == FD_READY, "op when not ready");
  fdth->op = luaL_checkinteger(L, 2);
  ASSERT(L, (FD_EXITED < fdth->op) && (fdth->op < FD_INVALID), "invalid op");
  fdth->start = lua_isnoneornil(L, 3) ? fdth->start : luaL_checkinteger(L, 3);
  fdth->end   = lua_isnoneornil(L, 4) ? fdth->end   : luaL_checkinteger(L, 4);
  ASSERT(L, fdth->start >= 0,      "invalid start index %I", fdth->start);
  ASSERT(L, fdth->end   >= 0,      "invalid end index %I", fdth->end);
  ASSERT(L, fdth->end   < IO_SIZE, "end too large (%I)", fdth->end);
  sem_post(&fdth->sem);
  return 0;
}

// ---------------------
// -- Registry
static const struct luaL_Reg civix_lib[] = {
  {"strerrno", l_strerrno},
  {"epoch", l_epoch}, {"mono",  l_mono},
  {"nanosleep", l_nanosleep},
  {"dir", l_dir}, {"pathstat", l_pathstat},
  {"mkdir", l_mkdir}, {"rm",  l_rm}, {"rmdir", l_rmdir},
  {"rename", l_rename}, {"exists", l_exists},
  {"sh", l_sh},
  {"fdopen", l_fdopen}, {"fdread", l_fdread}, {"fdwrite", l_fdwrite},
  {"filenostat", l_filenostat}, {"fdsetblocking", l_fdsetblocking},
  {"fdth", l_fdth_create},
  {NULL, NULL}, // sentinel
};

int luaopen_civix_lib(LS *L) {
  // civix.Dir metatable
  luaL_newmetatable(L, DIR_META);    // stack: Dir
    L_setmethod(L, "__gc", l_dir_gc);

  // civix.Sh metatable: {__gc=l_sh_gc, __index={...}}
  luaL_newmetatable(L, SH_META);
    L_setmethod(L, "__gc", l_sh_gc);
    lua_pushstring(L, "__index"); lua_createtable(L, 0, 3);
      L_setmethod(L, "isDone", l_sh_isDone);
      L_setmethod(L, "wait",   l_sh_wait);
      L_setmethod(L, "rc",     l_sh_rc);
    lua_settable(L, -3); // Sh.__index = {isDone=l_sh_isDone ...}

  luaL_newmetatable(L, FD_META);
    L_setmethod(L, "__gc", l_fdclose);
    lua_pushstring(L, "__index"); lua_createtable(L, 0, 5);
      L_setmethod(L, "close",    l_fdclose);
      L_setmethod(L, "tofile",   l_fdtofile);
      L_setmethod(L, "fileno",   l_fdfileno);
    lua_settable(L, -3); // Sh.__index = {isDone=l_sh_isDone ...}

  luaL_newmetatable(L, FDTH_META);
    L_setmethod(L, "__gc", l_fdth_destroy);
    lua_pushstring(L, "__index"); lua_createtable(L, 0, 9);
      L_setmethod(L, "destroy",  l_fdth_destroy);
      L_setmethod(L, "start",    l_fdth_start);
      L_setmethod(L, "end",      l_fdth_end);
      L_setmethod(L, "fileno",   l_fdth_fileno);
      L_setmethod(L, "error",    l_fdth_error);
      L_setmethod(L, "isDone",   l_fdth_isDone);
      L_setmethod(L, "isExited", l_fdth_isExited);
      L_setmethod(L, "_fill",    l_fdth_fill);
      L_setmethod(L, "_runop",   l_fdth_runop);
      L_setmethod(L, "_buf",     l_fdth_buf);
    lua_settable(L, -3); // Sh.__index = {isDone=l_sh_isDone ...}

  #define L_setindexasmt(L, NAME, META) \
    luaL_getmetatable(L, META); lua_getfield(L, -1, "__index"); \
    lua_setfield(L, -3, NAME); lua_settop(L, -2);
  luaL_newlib(L, civix_lib); // civix.lib
  lua_createtable(L, 0, 2);  // lib.indexes
    L_setindexasmt(L, "Sh",   SH_META);
    L_setindexasmt(L, "Fd",   FD_META);
    L_setindexasmt(L, "FdTh", FDTH_META);
  lua_setfield(L, -2, "indexes");

  #define setconstfield(L, CONST) \
    lua_pushinteger(L, CONST); lua_setfield(L, -2, #CONST)
  lua_createtable(L, 0, 6); // lib.consts
    setconstfield(L, IO_SIZE);

    // open constants
    setconstfield(L, O_RDONLY); setconstfield(L, O_WRONLY);
    setconstfield(L, O_RDWR);   setconstfield(L, O_APPEND);
    setconstfield(L, O_CREAT);  setconstfield(L, O_TRUNC);
    setconstfield(L, O_NONBLOCK);

    // stmodestring constants
		setconstfield(L, S_IFMT);
		setconstfield(L, S_IFSOCK); setconstfield(L, S_IFLNK);
		setconstfield(L, S_IFREG);  setconstfield(L, S_IFBLK);
		setconstfield(L, S_IFDIR);  setconstfield(L, S_IFCHR);
		setconstfield(L, S_IFIFO);

    // fdth._runop constants
    setconstfield(L, FD_EXIT);  setconstfield(L, FD_READY);
    setconstfield(L, FD_CLOSE); setconstfield(L, FD_OPEN);
    setconstfield(L, FD_SEEK);
    setconstfield(L, FD_READ);  setconstfield(L, FD_WRITE);

    // important errno's
    setconstfield(L, EEXIST);

  lua_setfield(L, -2, "consts");
  return 1;
}
