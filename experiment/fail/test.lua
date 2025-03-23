local T = require'civtest'.Test()
local fail = require'fail'

local failed = fail.failed

T.basic = function()
  local f = fail{'bad i=%i', 42}
  T.eq(true,  failed(f))
  T.eq(false, failed'ok')
  T.eq(false, failed())
  T.eq('bad i=42', tostring(f))

  f = fail.check(false, 'check failed')
  T.eq(fail{'check failed'}, f)
  T.eq('ok', fail.check('ok', 'check failed'))

  T.eq({1, 2, 3}, {fail.assert(1, 2, 3)})
  local err = "expect failed"
  T.throws(err, function()
    fail.assert(false, 'expect failed', 3)
  end)
  T.throws(err, function()
    fail.assert(fail{'%s failed', 'expect'}, 2, 3)
  end)
end
