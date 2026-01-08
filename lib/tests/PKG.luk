local P = {}

local lua = import'sys:lua.luk'

local deps = {
  'civ:lib/ds/testing',
  'civ:lib/lines/testing',
  'civ:lib/pod/testing',
}

local function test(src)
  P[src:match'([^.]*)'] = lua.test { src = src, dep = deps}
end

P.test_metaty  = lua.test { src = 'test_metaty.lua'  }
P.test_fmt     = lua.test { src = 'test_fmt.lua'     }
P.test_civtest = lua.test { src = 'test_civtest.lua' }
P.test_shim    = lua.test { src = 'test_shim.lua'    }
P.test_lap     = lua.test { src = 'test_lap.lua'     }

test'test_ds.lua'
test'test_ds_IFile.lua'

test'test_lines_diff.lua'
test'test_lines_file.lua'
test'test_lines_buffer.lua'
test'test_lines_kev.lua'
test'test_lines_motion.lua'
test'test_lines.lua'

test'test_pod.lua'
test'test_lson.lua'
test'test_civix.lua'
test'test_asciicolor.lua'
test'test_vt100.lua'

P.test_fd = lua.test {
  src = 'test_fd.lua',
  dep = { 'civ:lib/fd' },
}

return P
