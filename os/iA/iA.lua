local G = G or _G

--- intermediate Assembly
local M = G.mod and G.mod'iA' or {}

--- iA submodule containing all modules
--- (both user-defined and native).
---
--- Modules contain their own types.
M.mod = G.mod and G.mod'iA.mod' or {}

--- iA default core module, containing core types and functions.
M.core = G.mod and G.mod'iA.core' or {}

--- iA array module, containing all array types used in code.
--- Get or fetch an array type by calling it with the inner type.
M.array = G.mod and G.mod'iA.array' or setmetatable({}, {})

local C = M.core
M.mod.core, M.mod.array = C, M.array

local mty = require'metaty'
local ds = require'ds'
local fmt = require'fmt'

local push, pop, sfmt    = table.insert, table.remove, string.format

M.Reg = mty.enum'Reg' {
  NONE = 0, -- no register selected

  -- Corruptable input/output registers
  -- Input order:  A B D E F G H  (note: no C)
  -- Output order: C A B D
  --- Accumulator register.
  A = 1,
  B = 2,
  --- Count register, used in branch-if-zero
  C = 3,
  D = 4,

  -- Corruptable registers, additional inputs.
  E = 5, F = 6, G = 7, H = 8,

  -- non-corruptable registers for general use.
  I = 9, J = 10, K = 11, L = 12, M = 13, N = 14, O = 15, P = 16,

  -- corruptable registers used as temporaries.
  Q = 17, R = 18,

  --- corruptable "source" or temporary
  S = 19,
  --- corruptable "to" (aka destination) or temporary
  T = 20,

  U = 21, -- "universal" value stored on the heap
  V = 22, -- "value", aka a local value stored on the stack
  W = 23, -- reserved for "world" value, aka thread-global.

  -- reserved and unused
  X = 24, Y = 25, Z = 26,

  --- Not used in syntax, used in instruction.
  I2=28, I4=29, I8=30, -- 2,4,8 byte immediate
  OFS=31, -- offset
}

M.TyKind = mty.enum'TyKind' {
  UNKNOWN = 0, -- an unknown type.
  NATIVE  = 1, -- a native type such as an integer.
  CSTR    = 2, -- a counted string.
  ARRAY   = 3, -- an array with a U4 len, U4 cap, then the data.
  ENUM    = 4, -- a user-defined enum.
  STRUCT  = 5, -- a user-defined struct.
}

--- iA Type, either user-defined (i.e. struct, enum) or native.
M.Ty = mty'Ty' {
  'mod  [iA.Mod]: the module the type is defined in.',
  'name [str]: the name of the type.',
  'sz   [int?]: the size of the type in bytes, or nil if unknown.',
  'ref  [int]: the number of & reference levels of the type', ref = 0,
  'kind [iA.TyKind]: the kind of type',
  'field [table[string, int]]: STRUCT/ENUM only, map of name -> idx.',
}

local native = function(name, sz)
  return M.Ty{mod=C, name=name, sz=sz, ref=0, kind=M.TyKind.NATIVE}
end

C.U1, C.U2 = native('U1', 1), native('U2', 2)
C.U4, C.U8 = native('U4', 4), native('U8', 8)

C.I1, C.I2 = native('I1', 1), native('I2', 2)
C.I4, C.I8 = native('I4', 4), native('I8', 8)

--- Note: platforms may mutate this size
C.Int = native('Int', 4)

--- Note: platforms may mutate this size
C.UInt = native('UInt', 4)

local userTyCheck = function(t)
  assert(t.fields, 'user type must have fields table')
  for f, i in pairs(t.fields) do
    if not t[i] then error('field '..f..' is missing type') end
  end
end

--- Create or fetch an array with inner-type.
M.array.__call = function(_, ty)
  assert(mty.ty(ty) == M.Ty)
  local name = sfmt('[%s.%s]', ty.mod.name, ty.name)
  local a = rawget(M.array, name); if a then
    if a[1] ~= ty then
      error('duplicate array name: '..t.name)
    end
    return a
  end
  a = M.Ty{a, mod=M.array, name=name, kind=M.TyKind.ARRAY}
  M.array[name] = a
  return a
end

--- Create a new struct type
M.struct = function(t)
  assert(t.mod, 'missing mod'); assert(t.name, 'missing name')
  userTyCheck(t)
  t.kind = M.TyKind.STRUCT
  return M.Ty(t)
end

--- Create a new enum type
C.enum = function(t)
  assert(t.mod, 'missing mod'); assert(t.name, 'missing name')
  userTyCheck(t)
  t.kind = M.TyKind.ENUM
  return M.Ty(t)
end

--- Named register or memory location and its type.
M.Var = mty'Var' {
  'reg [iA.Reg]: register type (or V/U/etc)',
  'ty  [iA.Ty]: the type of the variable.',
 [[scope: the scope where the variable is active for
          (Mod, Fn, Block, etc)]],
  'cap [int]: the max capacity of a non-ref array type, or nil',
}

--- A literal value.
M.Literal = mty'Literal' { 'ty [iA.Ty]', 'value' }

M.Expr1Kind = mty.enum'Expr1Kind' {
  --- Named variable or literal
  VAL = 1,
  --- single-assignment with optional operator.
  EQ1 = 2,
  --- function call which returns one register.
  FN1 = 3,
}

--- Cross-platofrm operations. Operations work on an l and r values which are
--- an iA.Reg.
---
--- [{h1}CivCPU]
--- This enum is intended to be used with a 16bit virtual CPU,
--- called the CivCPU. The primary purpose of CivCPU is for
--- unit-testing and development of this library. It offers a
--- simple and inspectable runtime for crafting iA code.
---
--- The 16bit instruction format for CivCPU is:
--- [#
---   5b left  5b right  6b op
---   lllll    rrrrr     oooooo
---   0xF800   0x07C0    0x003F  (mask)
--- ]#
--- Where: [+
--- * [*o] operation (iA.Op) is low bits 0-5          (6 bits)
--- * [*l] left register (iA.Reg) is middle bits 6-10 (5 bits)
--- * [*r] right register (iA.Reg) is high bits 11-15 (5 bits)
--- ]
---
--- For some iA.Reg values, the instruction will be followed with
--- one or more 16bit immediate values. [+
--- * [*V]: an immediate offset of the stack pointer.
--- * [*L2, L4, L8]: immediate of the given bytes.
--- * [*OFS]: 16bit immediate of 5 bit iA.Reg followed by an 11bit offset.
--- ]
M.Op = mty.enum'Op' {
  INT  = 0,  -- CPU interrupt. Used for errors and kernel stuff.
  REGL = 1, -- l = reg(r): load from a system register
  REGS = 2, -- reg(l) = r: store to a system register

  -- stack and jump operations
  SP   = 3, -- sp(l): increment/decrement sp by literal
  PUSH = 4, -- push(l,r): push value/s to stack
  POP  = 5, -- pop(l,r): pop value/s from stack into register/s
  CALL = 6, -- call(l): call procedure at l
  RET  = 7, -- return from procedure
  CMP  = 8, -- cmp(l,r): compare and set flags register
  JMP  = 9, -- jmpif imm == (l&imm): l can be 0 (flags) or a reg.

  -- l = r: set l to r
  MOV = 16,

  -- l @= r: fetch value of size at address r
  FT1=17, FT2=18, FT4=19, FT8=20,

  -- store(l, r): store value r of size at address l
  ST1=21, ST2=22, ST4=23, ST8=24,

  -- Unsigned bitwise operations
  INV = 25,  -- l ~= r: inversion
  OR  = 26,  -- l |= r: or
  AND = 27,  -- l |= r: and
  XOR = 28,  -- l = xor(l, r): exclusive or
  SHL = 29,  -- l <<= r: shift left
  SHR = 30,  -- l >>= r: shift right
  ROL = 31,  -- l = rotl(l, imm): rotate l left by imm
  ROR = 32,  -- l = rotr(l, imm): rotate l left by imm

  -- int multiplication.
  -- guaranteed optimized: A low, D high = mul(A, r)
  MUL = 40, IMUL = 41,

  -- int division.
  -- guaranteed optimized: A quot, D rem = div(D high, A low, r div)]
  DIV = 42, IDIV = 43,

  -- arithmetic
  NEG = 44,  -- l = -r: 2's compliment negation
  ADD = 45,  -- l += r
  SUB = 46,  -- l -= r
  MOD = 47,  -- l %= r

  --- The PRINT instruction causes a debug print of the cstr (byte-size + data)
  --- pointed to by l (typically a literal). Also pretty-prints r if set.
  --- It is mostly used for low-level debugging.
  PRINT = 63,
}

--- An expression which returns a single value or register. The number
--- of items in the list will depend on the kind: [+
--- * VAL: will contain one item, the Var or Literal.
--- * EQ1: will contain two items on both sides of equal and an op.
--- * FN1: will contain the function arguments and fn.
--- ]
M.Expr1 = mty'Expr1' {
  'kind [iA.Expr1Kind]',
  'op [iA.Op]: the operation being performed for EQ1',
  'fn [iA.Fn | iA.Var]: the function being called',
}

M.StmtKind = mty'StmtKind' {
  --- expression with single return
  EXPR1 = 1,
  --- Multi-assignment function call
  MULTI = 2,
  --- if/elif/else statement
  IF = 3,
  --- switch/case
  SWITCH = 4,
  --- loop
  LOOP = 5,
}


return M
