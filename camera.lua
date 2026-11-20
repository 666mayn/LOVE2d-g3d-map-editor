-- Orbit camera for the editor. Z is up (g3d's default).
-- All the maths is pure Lua so it can be tested; apply() pushes the result
-- into g3d.camera.
--
-- Picking and rendering must agree on which way "screen right" points. If the
-- cursor highlight ever appears mirrored left/right against your mouse, flip
-- `invertRight` (the editor binds this to F9).
local sin, cos, tan, sqrt, atan2 = math.sin, math.cos, math.tan, math.sqrt, math.atan2 or math.atan

local Camera = {}
Camera.__index = Camera

local function norm(x, y, z)
  local l = sqrt(x * x + y * y + z * z)
  if l == 0 then return 0, 0, 1 end
  return x / l, y / l, z / l
end

function Camera.new()
  return setmetatable({
    tx = 8, ty = 8, tz = 0,            -- orbit target
    yaw = math.rad(-50), pitch = math.rad(35), dist = 24,
    fov = math.rad(60), near = 0.1, far = 1500,
    invertRight = false,
    _applied = {},
  }, Camera)
end

function Camera:reset()
  self.tx, self.ty, self.tz = 8, 8, 0
  self.yaw, self.pitch, self.dist = math.rad(-50), math.rad(35), 24
end

function Camera:clamp()
  local lim = math.rad(89)
  if self.pitch > lim then self.pitch = lim elseif self.pitch < -lim then self.pitch = -lim end
  if self.dist < 1.5 then self.dist = 1.5 elseif self.dist > 600 then self.dist = 600 end
end

-- eye position
function Camera:position()
  local cp = cos(self.pitch)
  return self.tx + self.dist * cos(self.yaw) * cp,
         self.ty + self.dist * sin(self.yaw) * cp,
         self.tz + self.dist * sin(self.pitch)
end

-- forward, right, up unit vectors (up is the true screen-up)
function Camera:basis()
  local px, py, pz = self:position()
  local fx, fy, fz = norm(self.tx - px, self.ty - py, self.tz - pz)
  -- right-handed:  right = forward x worldUp
  local rx, ry, rz = norm(fy, -fx, 0)
  local ux, uy, uz = ry * fz - rz * fy, rz * fx - rx * fz, rx * fy - ry * fx -- right x forward
  if self.invertRight then rx, ry, rz = -rx, -ry, -rz end
  return fx, fy, fz, rx, ry, rz, ux, uy, uz
end

-- Ray through the pixel (mx, my) of a w*h viewport. Returns ox,oy,oz,dx,dy,dz.
function Camera:ray(mx, my, w, h)
  local ox, oy, oz = self:position()
  local fx, fy, fz, rx, ry, rz, ux, uy, uz = self:basis()
  local aspect = w / h
  local th = tan(self.fov / 2)
  local sx = (mx / w * 2 - 1) * th * aspect
  local sy = (1 - my / h * 2) * th
  local dx, dy, dz = norm(fx + rx * sx + ux * sy, fy + ry * sx + uy * sy, fz + rz * sx + uz * sy)
  return ox, oy, oz, dx, dy, dz
end

-- Inverse of ray(): where does world point (x, y, z) land on a w*h viewport?
-- Returns screen x, screen y, depth; or nil when the point is behind the camera.
function Camera:project(x, y, z, w, h)
  local ex, ey, ez = self:position()
  local fx, fy, fz, rx, ry, rz, ux, uy, uz = self:basis()
  local vx, vy, vz = x - ex, y - ey, z - ez
  local depth = vx * fx + vy * fy + vz * fz
  if depth <= self.near then return nil end
  local th = tan(self.fov / 2)
  local sx = (vx * rx + vy * ry + vz * rz) / depth
  local sy = (vx * ux + vy * uy + vz * uz) / depth
  return (sx / (th * (w / h)) + 1) / 2 * w, (1 - sy / th) / 2 * h, depth
end

-- Mouse-drag orbit
function Camera:orbit(dx, dy)
  self.yaw = self.yaw - dx * 0.006
  self.pitch = self.pitch + dy * 0.006
  self:clamp()
end

-- Pan the target in the screen plane (pixels in, world units out)
function Camera:pan(dx, dy, h)
  local _, _, _, rx, ry, rz, ux, uy, uz = self:basis()
  local k = (2 * tan(self.fov / 2) * self.dist) / h
  self.tx = self.tx - rx * dx * k + ux * dy * k
  self.ty = self.ty - ry * dx * k + uy * dy * k
  self.tz = self.tz - rz * dx * k + uz * dy * k
end

-- Move the target on the ground plane relative to the view direction
function Camera:move(forward, strafe, rise, dt)
  local speed = (6 + self.dist * 0.7) * dt
  local cy, sy = cos(self.yaw), sin(self.yaw)
  -- horizontal forward (eye -> target) = (-cos, -sin); its right-hand side = (-sin, cos)
  local sgn = self.invertRight and -1 or 1
  self.tx = self.tx + (-cy * forward - sy * strafe * sgn) * speed
  self.ty = self.ty + (-sy * forward + cy * strafe * sgn) * speed
  self.tz = self.tz + rise * speed
end

function Camera:zoom(steps)
  self.dist = self.dist * (0.88 ^ steps)
  self:clamp()
end

Camera.SIDE_PITCH = math.rad(6)
Camera.TILT_PITCH = math.rad(35)

-- T: top view; pressing it again tilts back to the normal 3/4 view
function Camera:topDown()
  if math.abs(self.pitch - math.rad(89)) < 1e-3 then self.pitch = Camera.TILT_PITCH
  else self.pitch = math.rad(89) end
end

-- V: horizontal (side) view; pressing it again tilts back to the 3/4 view
function Camera:sideView()
  if math.abs(self.pitch - Camera.SIDE_PITCH) < 1e-3 then self.pitch = Camera.TILT_PITCH
  else self.pitch = Camera.SIDE_PITCH end
end

-- Snap the view to a side of the map. 0=east(+X) 1=north(+Y) 2=west 3=south,
-- i.e. the camera sits on that side and looks inwards.
local HALF = math.pi / 2
function Camera:snapYaw(side)
  self.yaw = side * HALF
end

-- Rotate to the next / previous side (dir = +1 or -1), landing exactly on a
-- 90 degree step even from a free-orbit angle.
function Camera:turn(dir)
  local k = self.yaw / HALF
  local n = dir > 0 and math.floor(k + 1e-6) + 1 or math.ceil(k - 1e-6) - 1
  self.yaw = n * HALF
end

-- Which side the camera is on (0..3) or nil when between sides
function Camera:side()
  local k = self.yaw / HALF
  local r = math.floor(k + 0.5)
  if math.abs(k - r) < 1e-3 then return r % 4 end
end

function Camera:focus(x, y, z, dist)
  self.tx, self.ty, self.tz = x, y, z
  if dist then self.dist = dist end
  self:clamp()
end

-- Push into g3d.camera. lookAt() rebuilds the view matrix; the projection
-- only needs rebuilding when fov / aspect / clip planes change.
-- Optional eye / target override (used by the first-person play-test).
function Camera:apply(g3d, w, h, ex, ey, ez, tx, ty, tz)
  local c = g3d.camera
  local a = self._applied
  local aspect = w / h
  if a.fov ~= self.fov or a.aspect ~= aspect or a.near ~= self.near or a.far ~= self.far then
    c.fov, c.aspectRatio, c.nearClip, c.farClip = self.fov, aspect, self.near, self.far
    c.updateProjectionMatrix()
    a.fov, a.aspect, a.near, a.far = self.fov, aspect, self.near, self.far
  end
  if ex then
    c.lookAt(ex, ey, ez, tx, ty, tz)
  else
    local px, py, pz = self:position()
    c.lookAt(px, py, pz, self.tx, self.ty, self.tz)
  end
end

return Camera
