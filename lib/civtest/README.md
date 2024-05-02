# Civtest: absurdly simple test library

This is a no-frills test library (<100 LoC). It simply builds on `metaty` and
`ds` to provide the simplest possible needs for testing.

* `assertEq` does deep table comparison as well as handling `__eq`.
* `assertErrorPat` for asserting errors.
* `assertMatch` for string matching.
* `test("my test", function() assertEq(1, 2) -- fails end)` does exactly what
  you think. It ALSO:
  * Ensures no global variables were added
* `grequire'myModule'` allows you to quickly import your module contents as
  global. Don't do it except when you're lazily prototyping stuff. Prefer
  `ds.auto` for fast and easy imports

