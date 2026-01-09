-- holds the config table, returned at end.
local C = {}

-- the host operating system. This primarily affects
-- what build flags are used when compiling C code.
C.host_os = "linux"

-- A table of hubname -> /absolute/dir/path/
-- This should contain the "software hubs" (which contain HUB.lua files)
-- that you want your project to depend on when being built.
C.hubs = {
  -- This hub, which contains libraries and software for
  -- the civboot tech stack (along with this build tool).
  civ = "/home/rett/projects/civstack/",

  -- The sys hub, which contains system-specific rules for building
  -- source code.
  sys = "/home/rett/projects/civstack/sys/",
}

-- The directory where `civ build` and `civ test` puts files.
C.buildDir = '.civ/'

-- The directory where `civ install` puts files.
C.installDir = HOME..'.local/civ/'

return C -- return for civ to read.
