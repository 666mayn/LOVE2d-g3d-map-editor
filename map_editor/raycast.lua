-- Pure ray math. No LÖVE / g3d dependency.
local floor, abs, huge = math.floor, math.abs, math.huge

local R = {}

-- Walk a ray through the unit voxel grid (Amanatides & Woo DDA).
-- Direction must be normalised so `t` is a world distance.
-- isSolid(x, y, z) -> truthy when the cell blocks the ray.
-- Returns hx,hy,hz (hit cell), nx,ny,nz (face normal of the face that was
-- entered, pointing back toward the ray origin), t   -- or nil on a miss.
function R.voxel(ox, oy, oz, dx, dy, dz, maxDist, isSolid)
  local x, y, z = floor(ox), floor(oy), floor(oz)
  if isSolid(x, y, z) then return x, y, z, 0, 0, 0, 0 end

  local sx = dx > 0 and 1 or -1
  local sy = dy > 0 and 1 or -1
  local sz = dz > 0 and 1 or -1
  local tdx = dx ~= 0 and abs(1 / dx) or huge
  local tdy = dy ~= 0 and abs(1 / dy) or huge
  local tdz = dz ~= 0 and abs(1 / dz) or huge
  local tmx = dx > 0 and (x + 1 - ox) / dx or (dx < 0 and (ox - x) / -dx or huge)
  local tmy = dy > 0 and (y + 1 - oy) / dy or (dy < 0 and (oy - y) / -dy or huge)
  local tmz = dz > 0 and (z + 1 - oz) / dz or (dz < 0 and (oz - z) / -dz or huge)

  local nx, ny, nz, t = 0, 0, 0, 0
  while true do
    if tmx < tmy and tmx < tmz then
      x = x + sx; t = tmx; tmx = tmx + tdx; nx, ny, nz = -sx, 0, 0
    elseif tmy < tmz then
      y = y + sy; t = tmy; tmy = tmy + tdy; nx, ny, nz = 0, -sy, 0
    else
      z = z + sz; t = tmz; tmz = tmz + tdz; nx, ny, nz = 0, 0, -sz
    end
    if t > maxDist then return nil end
    if isSolid(x, y, z) then return x, y, z, nx, ny, nz, t end
  end
end

-- Ray vs axis-aligned box (slab method). Returns entry distance or nil.
function R.aabb(ox, oy, oz, dx, dy, dz, minx, miny, minz, maxx, maxy, maxz)
  local tmin, tmax = 0, huge
  local o = { ox, oy, oz }
  local d = { dx, dy, dz }
  local lo = { minx, miny, minz }
  local hi = { maxx, maxy, maxz }
  for i = 1, 3 do
    if abs(d[i]) < 1e-12 then
      if o[i] < lo[i] or o[i] > hi[i] then return nil end
    else
      local t1 = (lo[i] - o[i]) / d[i]
      local t2 = (hi[i] - o[i]) / d[i]
      if t1 > t2 then t1, t2 = t2, t1 end
      if t1 > tmin then tmin = t1 end
      if t2 < tmax then tmax = t2 end
      if tmin > tmax then return nil end
    end
  end
  return tmin
end

-- Ray vs the plane  axis = coord  (axis is 1, 2 or 3 for x, y, z).
-- Returns t (> 0) and the hit point, or nil.
function R.plane(ox, oy, oz, dx, dy, dz, axis, coord)
  local o = axis == 1 and ox or (axis == 2 and oy or oz)
  local d = axis == 1 and dx or (axis == 2 and dy or dz)
  if abs(d) < 1e-9 then return nil end
  local t = (coord - o) / d
  if t <= 0 then return nil end
  return t, ox + dx * t, oy + dy * t, oz + dz * t
end

return R
