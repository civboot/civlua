summary"Simple version control software"

pkg {
  name     = 'pvc',
  version  = '0.1-0',
  url      = 'git+http://github.com/civboot/civlua',
  homepage = "https://lua.civboot.org#Package_pvc",
  license  = "UNLICENSE",
  doc      = 'README.cxt',
}

P.pvc = lua {
  src = {
    'pvc.lua',
    'pvc/unix.lua'
  }
}
