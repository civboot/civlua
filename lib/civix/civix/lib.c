#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <stdbool.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include <time.h>     // Time
#include <dirent.h>   // Dir
#include <sys/stat.h> // Dir
#include <unistd.h>   // Shell
#include <signal.h>   // Shell

#if __APPLE__
#include <crt_externs.h>
#define environ (*_NSGetEnviron())
#endif

// see luaL_Stream
#ifndef LUA_FILEHANDLE
#define LUA_FILEHANDLE "FILE*"
#endif

#define ASSERT(L, OK, ...) \
  if(!(OK)) { luaL_error(L, __VA_ARGS__); }

#define L_setmethod(L, KEY, FN)                     \
  lua_pushstring(L, KEY); lua_pushcfunction(L, FN); \
  lua_settable(L, -3);


// Return a string array with null-terminated end.
// Note: you MUST free it.
static const char** checkstringarray(lua_State *L, int index, int* lenOut) {
  lua_len(L, index); int len = luaL_checkinteger(L, -1); lua_pop(L, 1);
  const char** arr = malloc(sizeof(char*) * (len + 1));
  for(int i = 0; i < len; i++) {
    lua_geti(L, index, i + 1); arr[i] = luaL_checkstring(L, -1); lua_pop(L, 1);
  }
  arr[len] = NULL; *lenOut = len;
  return arr;
}

// ---------------------
// -- Time
int gettime(lua_State *L, clockid_t clk_id) {
  struct timespec spec = {};
  clock_gettime(CLOCK_REALTIME, &spec);
  lua_pushinteger(L, spec.tv_sec);
  lua_pushinteger(L, spec.tv_nsec);
  return 2;
} int l_epoch(lua_State *L) { return gettime(L, CLOCK_REALTIME);  }
  int l_mono(lua_State *L)  { return gettime(L, CLOCK_MONOTONIC); }

// ---------------------
// -- Dir
const char* DIR_META = "civix.Dir";
const char* SH_META  = "civix.Sh";
#define toldir(L) (DIR**)luaL_checkudata(L, 1, DIR_META)

static void DIR_gc(DIR** dir) {
  if(*dir) { closedir(*dir); *dir = NULL; }
}
static int l_dir_gc(lua_State *L) {
  DIR_gc(toldir(L)); return 0;
}

// Each time called return next: (name, ftype) or nil
static int dir_iter(lua_State *L) {
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
    case DT_BLK:     lua_pushstring(L, "blk");     break;
    case DT_CHR:     lua_pushstring(L, "chr");     break;
    case DT_DIR:     lua_pushstring(L, "dir");     break;
    case DT_FIFO:    lua_pushstring(L, "fifo");    break;
    case DT_LNK:     lua_pushstring(L, "link");    break;
    case DT_REG:     lua_pushstring(L, "file");    break;
    case DT_SOCK:    lua_pushstring(L, "sock");    break;
    case DT_UNKNOWN: lua_pushstring(L, "unknown"); break;
    default:         lua_pushnil(L);
  }
  return 2;
}

// return (name, ftype) iterator. Skips "." and ".."
static int l_dir(lua_State *L) {
  const char* path = luaL_checkstring(L, 1);
  printf("!! dir %s\n", path);
  DIR** dir = (DIR**)lua_newuserdata(L, sizeof(DIR*)); // stack: dir
  luaL_setmetatable(L, DIR_META);
  ASSERT(L, *dir = opendir(path), "cannot open %s: %s", path, strerror(errno));
  lua_pushcclosure(L, dir_iter, 1);                    // stack: (empty)
  return 1;
}

// return (ftype)
static int l_ftype(lua_State *L) {
  struct stat sbuf = {0};
  const char* path = luaL_checkstring(L, 1);
  ASSERT(L, stat(path, &sbuf) == 0,
    "cannot stat %s: %s", path, strerror(errno));
  switch(S_IFMT & sbuf.st_mode) {
		case S_IFSOCK: lua_pushstring(L, "sock"); break;
		case S_IFLNK:  lua_pushstring(L, "link"); break;
		case S_IFREG:  lua_pushstring(L, "file"); break;
		case S_IFBLK:  lua_pushstring(L, "blk"); break;
		case S_IFDIR:  lua_pushstring(L, "dir"); break;
		case S_IFCHR:  lua_pushstring(L, "chr"); break;
		case S_IFIFO:  lua_pushstring(L, "fifo"); break;
    default:       lua_pushnil(L);
  }
  return 1;
}

// ---------------------
// -- Shell

// For some reason these are not exported (???)
// https://www.lua.org/source/5.2/liolib.c.html
typedef luaL_Stream LStream;
#define tolstream(L)    ((LStream *)luaL_checkudata(L, 1, LUA_FILEHANDLE))
static int io_fclose(lua_State *L) {
  LStream *p = tolstream(L);
  int res = 0; if(p->f) res = fclose(p->f);
  return luaL_fileresult(L, (res == 0), NULL);
}
static LStream *newfile (lua_State *L, FILE* f) {
  LStream *p = (LStream *)lua_newuserdata(L, sizeof(LStream));
  p->f = f; p->closef = &io_fclose;
  luaL_setmetatable(L, LUA_FILEHANDLE);
  return p;
}

struct sh {
  pid_t pid; const char** env; // note: env only set if needs freeing
  int rc;
};
#define tolsh(L) ((struct sh*)luaL_checkudata(L, 1, SH_META))
struct sh* sh_wait(struct sh* sh, int flags) {
  printf("!! sh_wait %i rc=%i\n", sh->pid, sh->rc);
  if(sh->pid) {
    siginfo_t infop = {0};
    if(waitid(P_PID, sh->pid, &infop, WEXITED | flags)) {
      printf("!! sh_wait failed miserably\n");
      sh->rc = -99; return sh; // TODO: need better error handle here
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
static int l_sh_gc(lua_State *L) { sh_gc(tolsh(L)); return 0; }

// () -> isDone: asynchronously determine whether Sh is done.
static int l_sh_isDone(lua_State *L) {
  lua_pushboolean(L, sh_wait(tolsh(L), WNOHANG)->pid);
  return 1;
}

static int l_sh_rc(lua_State *L) {
  lua_pushinteger(L, tolsh(L)->rc);
  return 1;
}

// () -> : block until Sh is done.
static int l_sh_wait(lua_State *L) { sh_wait(tolsh(L), 0); return 0; }

// sh(command, {args}, environ=current) -> Sh, r, w, lr
static int l_sh(lua_State *L) {
  while(lua_gettop(L) < 3) lua_pushnil(L);
  int _len; int p[2]; char* err = "";
  const char** argv = NULL;
  int pr_r = 0, pr_w = 0, pr_lr = 0, ch_r = 0, ch_w = 0, ch_lw = 0;
  FILE *r = NULL, *w = NULL, *lr = NULL;
  struct sh* sh = (struct sh*)lua_newuserdata(L, sizeof(struct sh));
  sh->pid = 0; sh->rc = -1; sh->env = NULL;
  const char* command = luaL_checkstring(L, 1);
  if(!lua_isnil(L, 2)) { argv = checkstringarray(L, 2, &_len); }
  if(!lua_isnil(L, 3)) { sh->env = checkstringarray(L, 3, &_len); }

  lua_rotate(L, 1, 1); // move sh to bottom of stack
  lua_settop(L, 1);    // clear stack except for sh
  luaL_setmetatable(L, SH_META);

  err = "pipe exhaustion";
  if(pipe(p)) { goto error; } pr_r  = p[0]; ch_w  = p[1];
  if(pipe(p)) { goto error; } ch_r  = p[0]; pr_w  = p[1];
  if(pipe(p)) { goto error; } pr_lr = p[0]; ch_lw = p[1];
  printf("!! ch pipes: %i %i %i\n", ch_r, ch_w, ch_lw);
  printf("!! pr pipes: %i %i %i\n", pr_r, pr_w, pr_lr);

  err = "fdopen failure";
  if((r  = fdopen(pr_r,  "r")) == NULL) goto error;
  if((w  = fdopen(pr_w,  "w")) == NULL) goto error;
  if((lr = fdopen(pr_lr, "r")) == NULL) goto error;

  err = "fork failure";
  pid_t pid = fork(); if(pid == -1 ) {
    error:
  	if(r)  fclose(r);  else if (pr_r)  close(pr_r);
  	if(w)  fclose(w);  else if (pr_w)  close(pr_w);
  	if(lr) fclose(lr); else if (pr_lr) close(pr_lr);
    if(ch_r) close(ch_r);  if(ch_w) close(ch_w);  if(ch_lw) close(ch_lw);
    if(sh)   sh_gc(sh);
    luaL_error(L, "failed sh (%s): %s", err, strerror(errno));
  }
  if(pid == 0) { // child process
    fprintf(stderr, "!! child started\n");
    // close parent fds on child's side
    fclose(r); fclose(w); fclose(lr);

    // replace the std(in/out/err) file descriptors with our pipes
    close(ch_r); close(ch_lw); // FIXME: remove
    // dup2(ch_r,  STDIN_FILENO);  close(ch_r);
    dup2(ch_w,  STDOUT_FILENO); close(ch_w);
    // dup2(ch_lw, STDERR_FILENO); close(ch_lw);

    fprintf(stderr, "!! env: %p\n", sh->env);
    if(sh->env) environ = (char**)sh->env;

    fprintf(stderr, "!! executing: %s\n", command);
    for(char** arg = (char**)argv; *arg; arg++) {
      fprintf(stderr, "!!   arg: %s\n", *arg);
    }
    int err = execvp(command, (char**)argv);
    fprintf(stderr, "!! after execvp %i\n", errno);
    exit(errno);
  } // else parent process
  close(ch_r); close(ch_w); close(ch_lw);
  sh->pid = pid;
	newfile(L, r); newfile(L, w); newfile(L, lr);
  return 4;
}

// ---------------------
// -- Registry
static const struct luaL_Reg civix_lib[] = {
  {"epoch", l_epoch}, {"mono",  l_mono}, // Time
  {"dir", l_dir}, {"ftype", l_ftype},    // Dir
  {"sh", l_sh},                          // Shell
  {NULL, NULL}, // sentinel
};

int luaopen_civix_lib(lua_State *L) {
  // civix.Dir metatable
  luaL_newmetatable(L, DIR_META);    // stack: Dir
  lua_pushstring(L, "__gc");         // stack: Dir, "__gc"
  lua_pushcfunction(L, l_dir_gc);    // stack: Dir, "__gc", l_dir_gc
  lua_settable(L, -3);               // stack: Dir

  // civix.Sh metatable: {__gc=l_sh_gc, __index={...}}
  luaL_newmetatable(L, SH_META);
    L_setmethod(L, "__gc", l_sh_gc);
    lua_pushstring(L, "__index"); lua_createtable(L, 0, 1);
      L_setmethod(L, "isDone", l_sh_isDone);
      L_setmethod(L, "wait",   l_sh_wait);
      L_setmethod(L, "rc",     l_sh_rc);
    lua_settable(L, -3); // Sh.__index = {isDone=l_sh_isDone ...}

  lua_settop(L, 0); // clear stack
  luaL_newlib(L, civix_lib);
  return 1;
}
