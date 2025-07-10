local G = G or _G

--- intermediate Assembly
local M = G.mod and G.mod'iA' or {}

local mty = require'metaty'
local ds = require'ds'
local fmt = require'fmt'

local push, pop, sfmt    = table.insert, table.remove, string.format

M.Reg = mty.enum'Reg' {
  -- Input / Output registers.
  A = 1, -- Accumulator. First input, second output
  B = 2, -- Second input, third output
  C = 3, -- Count/branch. First output, not an input.
  D = 4, -- Fourth output.

  -- Corruptable registers, additional inputs.
  E = 5, F = 6, G = 7, H = 8,

  -- non-corruptable registers for general use.
  I = 9, J = 10, K = 11, L = 12, M = 13, N = 14, O = 15, P = 16,

  -- corruptable regiseters used as temporaries.
  -- S and T are used for memory instructions like memcpy.
  Q = 17, R = 18, S = 19, T = 20,

  U = 21, -- "universal" value stored on the heap
  V = 22, -- "value", aka a local value stored on the stack
  W = 23, -- reserved for "world" value, aka thread-global.

  -- reserved: 24 - 32
  X = 24, Y = 25, Z = 26,

  -- stack pointer holding the "top" of stack at the lowest
  -- memory address.
  sp = 32,

  fs = 33, -- floating point stack
}

M.Var = mty'Var' {
  'reg [iA.Reg]: register type (or V/U/etc)',
}


return M
