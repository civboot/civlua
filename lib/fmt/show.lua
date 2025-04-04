MAIN={}; require'civ'.setupFmt()

io.fmt {
  string='this is a string',
  int = 442,
  bool=true,
  fn=function() end,
  [42]='the answer',
}
