-- Minimal first-person walker with AABB-vs-voxel collision. Used by the
-- editor's play-test mode (F5) and handy as a starting point in your game.
-- Pure Lua: feed it a Map and an input table, read position back.
local floor, sqrt, sin, cos, ceil, abs = math.floor, math.sqrt, math.sin, math.cos, math.ceil, math.abs

local Walker = {}
Walker.__index = Walker

local EPS = 1e-4

function Walker.new(x, y, z, opts)
  opts = opts or {}
  return setmetatable({
    x = x, y = y, z = z,            -- feet position (x,y centred, z bottom)
    vx = 0, vy = 0, vz = 0,
    yaw = opts.yaw or 0, pitch = 0, -- radians; yaw 0 faces +x
    halfWidth = opts.halfWidth or 0.3,
    height = opts.height or 1.75,
    eye = opts.eye or 1.6,
    speed = opts.speed or 5, run = opts.run or 8.5,
    gravity = opts.gravity or 26, jump = opts.jump or 8.5,
    onGround = false,
    fly = false,
  }, Walker)
end

local function hits(map, x, y, z, hw, h)
  return map:boxHitsSolid(x - hw, y - hw, z, x + hw, y + hw, z + h)
end

-- Move along one axis in small steps so we can never tunnel through a block.
function Walker:_moveAxis(map, axis, delta)
  if delta == 0 then return false end
  local hw, h = self.halfWidth, self.height
  local steps = ceil(abs(delta) / 0.25)
  local step = delta / steps
  for _ = 1, steps do
    local nx, ny, nz = self.x, self.y, self.z
    if axis == 1 then nx = nx + step elseif axis == 2 then ny = ny + step else nz = nz + step end
    if hits(map, nx, ny, nz, hw, h) then
      -- snap flush against the block we ran into
      if axis == 1 then
        self.x = step > 0 and (floor(nx + hw) - hw - EPS) or (floor(nx - hw) + 1 + hw + EPS)
      elseif axis == 2 then
        self.y = step > 0 and (floor(ny + hw) - hw - EPS) or (floor(ny - hw) + 1 + hw + EPS)
      else
        self.z = step > 0 and (floor(nz + h) - h - EPS) or (floor(nz) + 1 + EPS)
      end
      return true
    end
    self.x, self.y, self.z = nx, ny, nz
  end
  return false
end

-- input: {forward=-1..1, strafe=-1..1, jump=bool, run=bool, up=-1..1 (fly)}
-- Forward at yaw 0 is +x; strafe +1 moves to the walker's right.
function Walker:update(map, dt, input)
  dt = math.min(dt, 1 / 20)
  local f, s = input.forward or 0, input.strafe or 0
  local len = sqrt(f * f + s * s)
  if len > 1 then f, s = f / len, s / len end
  local sp = input.run and self.run or self.speed
  local cy, sy = cos(self.yaw), sin(self.yaw)
  -- right-hand vector of forward (cy, sy) in a Z-up world is (sy, -cy)
  local wishx = (cy * f + sy * s) * sp
  local wishy = (sy * f - cy * s) * sp

  if self.fly then
    self.vx, self.vy, self.vz = wishx, wishy, (input.up or 0) * sp
  else
    self.vx, self.vy = wishx, wishy
    self.vz = self.vz - self.gravity * dt
    if self.vz < -50 then self.vz = -50 end
    if input.jump and self.onGround then self.vz = self.jump end
  end

  self:_moveAxis(map, 1, self.vx * dt)
  self:_moveAxis(map, 2, self.vy * dt)
  local hitZ = self:_moveAxis(map, 3, self.vz * dt)
  if hitZ then
    self.onGround = self.vz < 0
    self.vz = 0
  else
    self.onGround = false
  end
end

function Walker:eyePosition()
  return self.x, self.y, self.z + self.eye
end

-- direction the eye is looking
function Walker:lookVector()
  local cp = cos(self.pitch)
  return cos(self.yaw) * cp, sin(self.yaw) * cp, sin(self.pitch)
end

function Walker:look(dx, dy, sensitivity)
  sensitivity = sensitivity or 0.0025
  self.yaw = self.yaw - dx * sensitivity
  self.pitch = math.max(-1.55, math.min(1.55, self.pitch - dy * sensitivity))
end

return Walker
