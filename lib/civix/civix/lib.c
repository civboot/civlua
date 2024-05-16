#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <errno.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include <unistd.h>
#include <dirent.h>
#include <time.h>
#include <poll.h>
#include <signal.h>
#include <sys/wait.h>
#include <sys/stat.h>

// ---------------------
// -- Utilities
typedef lua_State LS;

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
// -- FILE
#ifndef LUA_FILEHANDLE
#define LUA_FILEHANDLE "FILE*"
#endif
#define tolstream(L)    ((luaL_Stream *)luaL_checkudata(L, 1, LUA_FILEHANDLE))
static int l_ffileno(LS* L) {
  lua_pushinteger(L, fileno(tolstream(L)->f)); return 1;
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
  mode_t mode = luaL_optinteger(L, 2, 0777);
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
  DIR** dir = (DIR**)lua_newuserdata(L, sizeof(DIR*)); // stack: dir
  luaL_setmetatable(L, DIR_META);
  ASSERT(L, *dir = opendir(path), "cannot open %s: %s", path, SERR);
  lua_pushcclosure(L, dir_iter, 1);                    // stack: (empty)
  return 1;
}

// pathstat(path) -> st_mode
// * st_mode: see consts.S_*
static int l_stmode(LS *L) {
  struct stat sbuf = {0};
  const char* path = luaL_checkstring(L, 1);
  ASSERT(L, stat(path, &sbuf) == 0, "cannot stat %s: %s", path, SERR);
  lua_pushinteger(L, sbuf.st_mode);
  return 1;
}

static int l_fileno(LS* L) {
  lua_pushinteger(L, fileno(tolstream(L)->f)); return 1;
}

// fmode(fileno) -> st_mode
// See pathstat for constants.
static int l_fstmode(LS *L) {
  int fd = luaL_checkinteger(L, 1); struct stat sbuf = {0};
  ASSERT(L, fstat(fd, &sbuf) == 0, "fstat failed: %s", SERR);
  lua_pushinteger(L, sbuf.st_mode);
  return 1;
}

// ---------------------
// -- Shell
const char* SH_META  = "civix.Sh";

struct sh {
  pid_t pid; char** env; // note: env only set if needs freeing
  int rc;
};
#define tolsh(L) ((struct sh*)luaL_checkudata(L, 1, SH_META))
struct sh* sh_wait(struct sh* sh, int flags) {
  if(sh->pid) {
    siginfo_t infop = {0};
    if(waitid(P_PID, sh->pid, &infop, WEXITED | flags)) {
      fprintf(stderr, "ERROR: waitid failed\n");
      return sh;
    }
    if(infop.si_pid == sh->pid) {
      sh->pid = 0; sh->rc = infop.si_status;
    }
  }
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
static int l_sh_wait(LS *L) { 
  sh_wait(tolsh(L), 0);
  return 0; }

// (command, argList, envList=nil, stdin, out, err) -> (sh, r, w)
// Note: all file-descriptors are integers
// Note: file descriptors are only returned if they have been created
//   by pipe(), they are not returned if they were passed in.
#define CLOSE(fno) if(fno >= 0) close(fno)
static int l_sh(LS *L) {
  const char* command = luaL_checkstring(L, 1);
  char **env = NULL; int _unused;
  char **argv = checkstringarray(L, 2, &_unused);
  if(!lua_isnoneornil(L, 3)) { env = checkstringarray(L, 3, &_unused); }
  int inp = luaL_optinteger(L, 4, -1);
  int out = luaL_optinteger(L, 5, -1);
  int err = luaL_optinteger(L, 6, STDERR_FILENO);

  struct sh* sh = (struct sh*)lua_newuserdata(L, sizeof(struct sh));
  sh->pid = 0; sh->env = env;
  luaL_setmetatable(L, SH_META);

  // ch_r=child-read, pr_w=parent-write, etc
  int ch_r = -1, ch_w = -1; int pr_r = -1, pr_w = -1;
  int rw[2];
  if(inp >= 0) { ch_r = inp; } else {
    if(pipe(rw)) goto error; ch_r  = rw[0]; pr_w  = rw[1];
  }
  if(out >= 0) { ch_w = out; } else {
    if(pipe(rw)) goto error; pr_r  = rw[0]; ch_w  = rw[1];
  }

  int pid = fork(); if(pid == -1) goto error;
  else if(pid == 0) { // child
    CLOSE(pr_r); CLOSE(pr_w);
    if(ch_w != STDOUT_FILENO) { dup2(ch_w,  STDOUT_FILENO); close(ch_w); }
    if(ch_r != STDIN_FILENO)  { dup2(ch_r,  STDIN_FILENO);  close(ch_r); }
    if(err  != STDERR_FILENO) { dup2(err,   STDERR_FILENO); close(err);  }
    return execvp(command, argv);
  } // else parent
  sh->pid = pid;
  CLOSE(ch_w); CLOSE(ch_r);
  // only return if we created the fileno
  if(out >= 0) lua_pushnil(L); else lua_pushinteger(L, pr_r);
  if(inp >= 0) lua_pushnil(L); else lua_pushinteger(L, pr_w);
  return 3;
  error:
    if(ch_r) close(ch_r); if(ch_w) close(ch_w);
    if(pr_r) close(pr_r); if(pr_w) close(pr_w);
    luaL_error(L, "failed sh (%s): %s", err, SERR); return 0;
}
#undef CLOSE


// ---------------------
// -- Registry
static const struct luaL_Reg civix_lib[] = {
  {"strerrno", l_strerrno},
  {"epoch", l_epoch}, {"mono", l_mono},
  {"nanosleep", l_nanosleep},
  {"dir", l_dir}, {"stmode", l_stmode},
  {"fileno", l_fileno}, {"fstmode", l_fstmode},
  {"mkdir", l_mkdir}, {"rm",  l_rm}, {"rmdir", l_rmdir},
  {"rename", l_rename}, {"exists", l_exists},
  {"sh", l_sh},
  {"ffileno", l_ffileno},
  {NULL, NULL}, // sentinel
};

int luaopen_civix_lib(LS *L) {
  luaL_newlib(L, civix_lib);

  luaL_newmetatable(L, DIR_META);
    L_setmethod(L, "__gc", l_dir_gc);
  lua_setfield(L, -2, "Dir");

  luaL_newmetatable(L, SH_META);
    L_setmethod(L, "__gc", l_sh_gc);
    lua_createtable(L, 0, 3); // __index table
      L_setmethod(L, "isDone", l_sh_isDone);
      L_setmethod(L, "wait",   l_sh_wait);
      L_setmethod(L, "rc",     l_sh_rc);
    lua_setfield(L, -2, "__index");
  lua_setfield(L, -2, "Sh");

  #define setconstfield(L, CONST) \
    lua_pushinteger(L, CONST); lua_setfield(L, -2, #CONST)
  // st_mode constants
  setconstfield(L, S_IFMT);
  setconstfield(L, S_IFSOCK); setconstfield(L, S_IFLNK);
  setconstfield(L, S_IFREG);  setconstfield(L, S_IFBLK);
  setconstfield(L, S_IFDIR);  setconstfield(L, S_IFCHR);
  setconstfield(L, S_IFIFO);

  // important errno's
  setconstfield(L, EEXIST);
  return 1;
}
