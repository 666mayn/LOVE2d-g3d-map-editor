-- Run from the project root:  texlua tests/test_world.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
local Map = require("map_editor.map")
local Camera = require("map_editor.camera")
local Mesher = require("map_editor.mesher")
local Walker = require("map_editor.walker")
local Entities = require("map_editor.entities")
local R = require("map_editor.raycast")

local passed, failed = 0, 0
local function check(name, cond, extra)
  if cond then passed = passed + 1
  else failed = failed + 1; print("FAIL: " .. name .. (extra and (" -> " .. tostring(extra)) or "")) end
end
local function near(a, b, e) return math.abs(a - b) <= (e or 1e-6) end

---------------------------------------------------------------- camera --
local cam = Camera.new()
cam.yaw, cam.pitch, cam.dist = 0, 0, 10 -- eye on +x axis looking toward -x
cam.tx, cam.ty, cam.tz = 0, 0, 0
local ex, ey, ez = cam:position()
check("eye position", near(ex, 10) and near(ey, 0) and near(ez, 0))
local ox, oy, oz, dx, dy, dz = cam:ray(400, 300, 800, 600) -- centre of screen
check("centre ray looks at target", near(dx, -1) and near(dy, 0) and near(dz, 0), dx .. "," .. dy .. "," .. dz)
local _, _, _, rdx, rdy, rdz = cam:ray(800, 300, 800, 600) -- right edge
check("right-edge ray leans toward world right", rdy ~= 0 and rdz == 0 or math.abs(rdz) < 1e-9)
-- Right-handed: looking toward -x with z up, screen-right is +y.
check("right-handed: screen right = +y here", rdy > 0, rdy)
local _, _, _, tdx, tdy, tdz = cam:ray(400, 0, 800, 600) -- top edge
check("top-edge ray tilts up", tdz > 0 and near(tdy, 0), tdz)
-- field of view: half-height angle equals fov/2
check("vertical fov", near(math.atan(tdz / -tdx) or 0, cam.fov / 2, 1e-6) or near(math.atan(tdz, -tdx), cam.fov / 2, 1e-6))
-- invertRight mirrors only the horizontal axis
cam.invertRight = true
local _, _, _, mdx, mdy = cam:ray(800, 300, 800, 600)
check("invertRight mirrors x", mdy < 0 and near(mdy, -rdy))
local _, _, _, mtx, mty, mtz = cam:ray(400, 0, 800, 600)
check("invertRight keeps vertical", near(mtz, tdz))
cam.invertRight = false
-- ray for any pixel is unit length
local _, _, _, a, b, c = cam:ray(123, 456, 800, 600)
check("unit direction", near(a * a + b * b + c * c, 1))
-- orbit clamp
cam:orbit(0, -100000); check("pitch clamped", cam.pitch >= math.rad(-89) - 1e-9)
cam:orbit(0, 1000000); check("pitch clamped hi", cam.pitch <= math.rad(89) + 1e-9)
cam:zoom(-1000); check("dist clamped hi", cam.dist <= 600); cam:zoom(1000); check("dist clamped lo", cam.dist >= 1.5)
-- pan moves the target perpendicular to the view
cam.yaw, cam.pitch, cam.dist, cam.tx, cam.ty, cam.tz = 0, 0, 10, 0, 0, 0
cam:pan(100, 0, 600)
check("pan right drags world left (target moves -y)", cam.ty < 0 and near(cam.tx, 0) and near(cam.tz, 0), cam.ty)
-- WASD: forward moves toward where the camera looks (-x here)
cam.tx, cam.ty, cam.tz = 0, 0, 0; cam:move(1, 0, 0, 1)
check("move forward", cam.tx < 0 and near(cam.ty, 0))
cam.tx, cam.ty = 0, 0; cam:move(0, 1, 0, 1)
check("strafe right = +y here", cam.ty > 0 and near(cam.tx, 0), cam.ty)
-- picking a known point: a ray through the screen centre hits a block at the target
local mm = Map.new(); mm:set(0, 0, 0, 1)
cam.yaw, cam.pitch, cam.dist, cam.tx, cam.ty, cam.tz = math.rad(30), math.rad(40), 12, 0.5, 0.5, 0.5
local rox, roy, roz, rdx2, rdy2, rdz2 = cam:ray(400, 300, 800, 600)
local hx, hy, hz = mm:raycast(rox, roy, roz, rdx2, rdy2, rdz2, 100)
check("centre ray picks the block under the target", hx == 0 and hy == 0 and hz == 0)

---------------------------------------------------------------- mesher --
local function faces(map)
  local total = 0
  for k, c in pairs(map.chunks) do total = total + #Mesher.buildChunk(map, c) / 6 end
  return total
end
local m1 = Map.new(); m1:set(0, 0, 0, 1)
check("single cube = 6 faces", faces(m1) == 6, faces(m1))
local m2 = Map.new(); m2:set(0, 0, 0, 1); m2:set(1, 0, 0, 1)
check("two touching cubes = 10 faces", faces(m2) == 10, faces(m2))
local m3 = Map.new(); m3:fillBox(0, 0, 0, 2, 2, 2, 1)
check("3x3x3 solid = 54 faces", faces(m3) == 54, faces(m3))
local m4 = Map.new(); m4:fillBox(14, 0, 0, 17, 0, 0, 1) -- spans a chunk border
check("cross-chunk bar = 4*4+2 faces", faces(m4) == 18, faces(m4))
-- water (non-solid, id 12) next to stone: stone face toward water drawn, water face toward stone culled
local m5 = Map.new(); m5:set(0, 0, 0, 3); m5:set(1, 0, 0, 12)
check("solid|water: 6 + 5 faces", faces(m5) == 11, faces(m5))
local m6 = Map.new(); m6:set(0, 0, 0, 12); m6:set(1, 0, 0, 12)
check("water|water culls shared face", faces(m6) == 10, faces(m6))
-- vertex format
local v = Mesher.buildChunk(m1, m1.chunks[Map.chunkKey(0, 0, 0)])
check("12 numbers per vertex", #v[1] == 12)
local okfmt = true
for _, vert in ipairs(v) do
  for i = 1, 12 do if type(vert[i]) ~= "number" then okfmt = false end end
  if vert[1] < 0 or vert[1] > 1 or vert[2] < 0 or vert[2] > 1 or vert[3] < 0 or vert[3] > 1 then okfmt = false end
end
check("all vertices numeric, inside unit cube", okfmt)
-- winding: every triangle must be counter-clockwise seen from outside (matches its normal), on all 6 faces,
-- including the flipped-diagonal AO case. Back-face culling hides triangles that are wound the other way.
local function windingOk(verts)
  for i = 1, #verts, 3 do
    local a, b, c = verts[i], verts[i + 1], verts[i + 2]
    local ux, uy, uz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
    local vx, vy, vz = c[1] - a[1], c[2] - a[2], c[3] - a[3]
    local cx, cy, cz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
    if cx * a[6] + cy * a[7] + cz * a[8] <= 0 then return false, i end
  end
  return true
end
check("every face of a block winds counter-clockwise from outside", windingOk(v))
local mw = Map.new(); mw:set(0, 0, 0, 1); mw:set(1, 1, 1, 1); mw:set(-1, 0, 1, 1); mw:set(0, 0, 2, 1)
check("winding stays correct with AO diagonal flips", windingOk(Mesher.buildChunk(mw, mw.chunks[Map.chunkKey(0, 0, 0)])))
check("cursor cube winds counter-clockwise too", windingOk(Mesher.cubeVerts(1, 1, 1, 1, true)))
-- shading: top brighter than bottom for the same block
local topSum, botSum = 0, 0
for _, vert in ipairs(v) do
  if vert[8] == 1 then topSum = topSum + vert[9] end
  if vert[8] == -1 then botSum = botSum + vert[9] end
end
check("top face brighter than bottom", topSum > botSum)
-- AO: a corner shaded by a neighbouring block must be darker than an open corner
local m7 = Map.new(); m7:set(0, 0, 0, 1); m7:set(1, 0, 1, 1) -- block sitting next to the top face of block 0
local verts7 = Mesher.buildChunk(m7, m7.chunks[Map.chunkKey(0, 0, 0)])
local lo, hi = 9, 0
for _, vert in ipairs(verts7) do
  if vert[8] == 1 and vert[3] == 1 and vert[1] <= 1 and vert[2] <= 1 and vert[11] and vert[1] >= 0 then
    if vert[9] < lo then lo = vert[9] end
    if vert[9] > hi then hi = vert[9] end
  end
end
check("ambient occlusion darkens a creased corner", lo < hi, lo .. " vs " .. hi)
-- uv rect
local m8 = Map.new(); m8.palette[1].uv = { 0.25, 0.5, 0.5, 0.75 }; m8:set(0, 0, 0, 1)
local v8 = Mesher.buildChunk(m8, m8.chunks[Map.chunkKey(0, 0, 0)])
local uvok = true
for _, vert in ipairs(v8) do
  if vert[4] < 0.25 - 1e-9 or vert[4] > 0.5 + 1e-9 or vert[5] < 0.5 - 1e-9 or vert[5] > 0.75 + 1e-9 then uvok = false end
end
check("palette uv rect respected", uvok)
-- update(): fake g3d, dirty bookkeeping, empty chunk drops its model
local made = 0
local fakeG3d = { newModel = function(verts, tex) made = made + 1; return { verts = verts, tex = tex } end }
local mm2 = Map.new(); mm2:fillBox(0, 0, 0, 20, 3, 3, 1)
local models = {}
local n = Mesher.update(mm2, models, fakeG3d, "tex")
-- (border blocks also dirty empty neighbour chunks, which are processed but need no model)
check("update builds a model for each real chunk", made == 2 and next(mm2.dirty) == nil, n .. "/" .. made)
check("update with nothing dirty is a no-op", Mesher.update(mm2, models, fakeG3d, "tex") == 0)
mm2:set(0, 0, 0, 0)
Mesher.update(mm2, models, fakeG3d, "tex")
check("editing one block rebuilds only the one existing chunk", made == 3, made)
mm2:clear(); Mesher.update(mm2, models, fakeG3d, "tex")
check("cleared map drops models", next(models) == nil)
local all = Mesher.buildAll(m3, fakeG3d, "t")
check("buildAll", all[Map.chunkKey(0, 0, 0)] ~= nil)

--------------------------------------------------------------- walker --
local wm = Map.new(); wm:fillBox(-20, -20, 0, 20, 20, 0, 1) -- floor top at z=1
local w = Walker.new(0.5, 0.5, 5)
for _ = 1, 120 do w:update(wm, 1 / 60, {}) end
check("falls and lands on the floor", near(w.z, 1, 0.01) and w.onGround, w.z)
-- wall at x = 4
wm:fillBox(4, -20, 1, 4, 20, 5, 3)
w.x, w.y, w.yaw = 0.5, 0.5, 0
for _ = 1, 240 do w:update(wm, 1 / 60, { forward = 1 }) end
check("stopped by a wall", w.x < 4 - w.halfWidth + 1e-3 and w.x > 3, w.x)
-- strafing: yaw 0 faces +x, right-handed right is -y
w.x, w.y = 0.5, 0.5
for _ = 1, 30 do w:update(wm, 1 / 60, { strafe = 1 }) end
check("strafe right moves toward -y at yaw 0", w.y < 0.5 and near(w.x, 0.5, 0.01), w.y)
-- jump clears a 1-block step but not a 2-block wall
w.x, w.y, w.yaw, w.z = 0.5, 0.5, 0, 1
wm:fillBox(2, -20, 1, 2, 20, 1, 3) -- a one-block-high ledge
for _ = 1, 20 do w:update(wm, 1 / 60, { forward = 1 }) end
check("ledge blocks walking", w.x < 2 - w.halfWidth + 1e-3, w.x)
w.x = 1.0
local jumped = false
for i = 1, 90 do
  w:update(wm, 1 / 60, { forward = 1, jump = true })
  if w.x > 2.5 then jumped = true end
end
check("jump gets over a 1-block ledge", jumped, w.x)
-- no tunnelling at a huge dt (clamped) and at high speed
w.x, w.y, w.z, w.yaw = 0.5, 0.5, 1, 0
w.run = 400; w.vx = 0
for _ = 1, 30 do w:update(wm, 0.05, { forward = 1, run = true }) end
check("never tunnels through a wall at 400 u/s", w.x < 4, w.x)
-- ceiling
local cm = Map.new(); cm:fillBox(-5, -5, 0, 5, 5, 0, 1); cm:fillBox(-5, -5, 4, 5, 5, 4, 1)
local cw = Walker.new(0, 0, 1)
for _ = 1, 60 do cw:update(cm, 1 / 60, { jump = true }) end
check("head hits the ceiling", cw.z + cw.height <= 4 + 1e-3, cw.z + cw.height)
-- look
cw:look(100, 100); check("pitch limited", math.abs(cw.pitch) <= 1.55)

------------------------------------------------------------- entities --
local idx = Entities.index(Entities.defaults)
check("default types indexed", idx.player_start and idx.light and idx.trigger)
local p = Entities.newProps(idx.light)
check("default props", p.intensity == 1 and p.color == "#ffffff")
local sw, sd, sh = Entities.size(idx.trigger, { props = { w = 4, d = 3, h = 5 } })
check("sizeProps read from entity", sw == 4 and sd == 3 and sh == 5)
local zw = Entities.size(idx.trigger, { props = { w = 0, d = "x", h = 1 } })
check("zero / bad size is sanitised", zw == 0.1)

print(string.format("%s: %d passed, %d failed", _VERSION, passed, failed))
os.exit(failed == 0 and 0 or 1)
