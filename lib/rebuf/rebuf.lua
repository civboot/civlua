-- This module contains an undo/redo buffer and Gap buffer, although
-- the Buffer can work on any object that supports a `lines` like interface.
--
-- Its purpose is to be used inside an editor or similar application.
local M = mod and mod'rebuf' or {}
return M
