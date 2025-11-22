summary'Print and export documentation.'

pkg {
  name    = 'doc',
  version = '0.1-0',
  url     = 'git+http://github.com/civboot/civlua',
  homepage = "https://lua.civboot.org#Package_doc",
  doc     = 'README.cxt',
}

P.doc = lua {
  src = {
    doc = 'doc.lua',
    ['doc.lua'] = 'lua.lua',
  },
}
