local P = {}

local lua = import'sys:lua.luk'

local deps = {
  'civ:lib/ds/testing',
  'civ:lib/lines/testing',
  'civ:lib/pod/testing',
}

P.test_metaty  = lua.test { src = 'test_metaty.lua'  }
P.test_fmt     = lua.test { src = 'test_fmt.lua'     }
P.test_civtest = lua.test { src = 'test_civtest.lua' }
P.test_shim    = lua.test { src = 'test_shim.lua'    }

P.test_ds        = lua.test { src = 'test_ds.lua', dep = deps }
P.test_ds_IFile  = lua.test { src = 'test_ds_IFile.lua', dep = deps }

P.test_lines_diff = lua.test { src = 'test_lines_diff.lua', dep = deps }
P.test_lines_file = lua.test { src = 'test_lines_file.lua', dep = deps }
P.test_lines      = lua.test { src = 'test_lines.lua', dep=deps }

P.test_lap     = lua.test { src = 'test_lap.lua'  }
P.test_pod     = lua.test { src = 'test_pod.lua', dep=deps }
P.test_lson    = lua.test { src = 'test_lson.lua', dep=deps }

P.test_civix   = lua.test { src = 'test_civix.lua', dep=deps }
P.test_asciicolor = lua.test { src = 'test_asciicolor.lua' }
P.test_vt100    = lua.test { src = 'test_vt100.lua' }

return P
