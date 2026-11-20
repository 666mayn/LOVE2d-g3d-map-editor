-- Undo / redo. A "transaction" groups everything done between begin() and
-- commit() into one undo step. Block edits are logged by Map:set() itself
-- (map._hist is set while a transaction is open); entity edits log closures.
local History = {}
History.__index = History

local LIMIT = 200

function History.new(map)
  return setmetatable({
    map = map,
    undoStack = {},
    redoStack = {},
    cur = nil,
    version = 0, -- bumps on every change; the editor compares it to the saved version
  }, History)
end

function History:begin()
  if self.cur then return end
  self.cur = { blocks = {}, ops = {} }
  self.map._hist = self
end

-- called by Map:set
function History:block(x, y, z, old, new)
  local b = self.cur.blocks
  local n = #b
  b[n + 1], b[n + 2], b[n + 3], b[n + 4], b[n + 5] = x, y, z, old, new
end

-- called by the entity methods on Map
function History:op(undoFn, redoFn)
  self.cur.ops[#self.cur.ops + 1] = { undoFn, redoFn }
end

function History:commit()
  local c = self.cur
  self.cur = nil
  self.map._hist = nil
  if c and (#c.blocks > 0 or #c.ops > 0) then
    self.undoStack[#self.undoStack + 1] = c
    if #self.undoStack > LIMIT then table.remove(self.undoStack, 1) end
    self.redoStack = {}
    self.version = self.version + 1
    return true
  end
  return false
end

-- Run fn inside a transaction. Always commits, even if fn errors.
function History:run(fn)
  self:begin()
  local ok, err = pcall(fn)
  self:commit()
  if not ok then error(err, 0) end
end

function History:cancel()
  -- abandon an open transaction by undoing whatever it already did
  local c = self.cur
  self.cur = nil
  self.map._hist = nil
  if c then self:_apply(c, true) end
end

function History:_apply(step, backwards)
  local m = self.map
  if backwards then
    local b = step.blocks
    for i = #b - 4, 1, -5 do m:set(b[i], b[i + 1], b[i + 2], b[i + 3]) end
    for i = #step.ops, 1, -1 do step.ops[i][1]() end
  else
    local b = step.blocks
    for i = 1, #b, 5 do m:set(b[i], b[i + 1], b[i + 2], b[i + 4]) end
    for i = 1, #step.ops do step.ops[i][2]() end
  end
end

function History:undo()
  assert(not self.cur, "cannot undo inside a transaction")
  local step = table.remove(self.undoStack)
  if not step then return false end
  self:_apply(step, true)
  self.redoStack[#self.redoStack + 1] = step
  self.version = self.version + 1
  return true
end

function History:redo()
  assert(not self.cur, "cannot redo inside a transaction")
  local step = table.remove(self.redoStack)
  if not step then return false end
  self:_apply(step, false)
  self.undoStack[#self.undoStack + 1] = step
  self.version = self.version + 1
  return true
end

function History:clear()
  self.undoStack, self.redoStack = {}, {}
  self.version = self.version + 1
end

return History
