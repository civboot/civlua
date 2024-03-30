#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include <time.h>   // Time
#include <string.h> // Dir
#include <dirent.h> // Dir
#include <errno.h>  // Dir
#include <sys/stat.h> // Dir
#include <stdio.h>

// see luaL_Stream
#ifndef LUA_FILEHANDLE
#define LUA_FILEHANDLE "FILE*"
#endif

#define ASSERT(L, OK, ...) \
  if(!(OK)) { luaL_error(L, __VA_ARGS__); }

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

typedef DIR** UdDir; // Userdata which handles GC
  static void UdDir_gc(UdDir dir) {
    if(*dir) { closedir(*dir); *dir = NULL; }
  }
  static int l_dir_gc(lua_State *L) {
    UdDir_gc((UdDir)lua_touserdata(L, 1)); return 0;
  }

// Each time called return next: (name, ftype) or nil
static int dir_iter(lua_State *L) {
	UdDir dir = (UdDir) lua_touserdata(L, lua_upvalueindex(1));
  if(*dir == NULL) return 0; // already freed
  struct dirent* ent;
  do {
    if((ent = readdir(*dir)) == NULL) {
      printf("!! dir_iter readdir==NULL\n");
      UdDir_gc(dir);
      return 0; // free early and return done
    }
    printf("!! dir_iter %s\n", ent->d_name);
    if((0==strcmp(".", ent->d_name)) || (0==strcmp("..", ent->d_name))) {
      printf("!!   is . or ..\n");
      continue;
    }
    break;
  } while(1);
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

// return (name, isDir) iterator
static int l_dir(lua_State *L) {
  const char* path = luaL_checkstring(L, 1);
  printf("!! dir %s\n", path);
  UdDir dir = (UdDir)lua_newuserdata(L, sizeof(UdDir)); // stack: dir
  luaL_getmetatable(L, DIR_META);                       // stack: dir, Dir
  lua_setmetatable(L, -2);                              // stack: dir
  ASSERT(L, *dir = opendir(path), "cannot open %s: %s", path, strerror(errno));
  lua_pushcclosure(L, dir_iter, 1); 										// stack: (empty)
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
// -- Registry
static const struct luaL_Reg civix_lib[] = {
  {"epoch", l_epoch}, {"mono",  l_mono}, // Time
  {"dir", l_dir}, {"ftype", l_ftype},    // Dir
  {NULL, NULL}, // sentinel
};

int luaopen_civix_lib(lua_State *L) {
  // civix.Dir metatable
  luaL_newmetatable(L, DIR_META);    // stack: Dir
  lua_pushstring(L, "__gc");         // stack: Dir, "__gc"
  lua_pushcfunction(L, l_dir_gc);    // stack: Dir, "__gc", l_dir_gc
  lua_settable(L, -3);               // stack: Dir
  lua_settop(L, 0);                  // stack: (empty)

  luaL_newlib(L, civix_lib);         // stack: civix.lib (library)
  return 1;
}

