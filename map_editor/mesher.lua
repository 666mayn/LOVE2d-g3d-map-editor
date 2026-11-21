-- Turns map chunks into g3d models: hidden faces are culled, every vertex
-- gets baked directional shading + ambient occlusion (so no lights needed).
-- Vertex layout is g3d's default:  x,y,z, u,v, nx,ny,nz, r,g,b,a
local floor = math.floor

local Mesher = {}

local CS = 16
local CS2 = CS * CS

-- Face table: normal n, tangents u,v, directional shade.
-- `flip` marks the faces where u x v points INTO the block (-x, +y, -z): their triangles are emitted in
-- reverse order so every face winds counter-clockwise seen from outside (back-face culling needs this).
local FACES = {
  { n = { 1, 0, 0 },  u = { 0, 1, 0 }, v = { 0, 0, 1 }, shade = 0.80 },
  { n = { -1, 0, 0 }, u = { 0, 1, 0 }, v = { 0, 0, 1 }, shade = 0.80, flip = true },
  { n = { 0, 1, 0 },  u = { 1, 0, 0 }, v = { 0, 0, 1 }, shade = 0.66, flip = true },
  { n = { 0, -1, 0 }, u = { 1, 0, 0 }, v = { 0, 0, 1 }, shade = 0.66 },
  { n = { 0, 0, 1 },  u = { 1, 0, 0 }, v = { 0, 1, 0 }, shade = 1.00 },
  { n = { 0, 0, -1 }, u = { 1, 0, 0 }, v = { 0, 1, 0 }, shade = 0.50, flip = true },
}
local AO = { [0] = 0.50, 0.70, 0.86, 1.00 } -- indexed by number of free neighbours
local CORNERS = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 } }

-- Returns a flat array of vertices (each a 12-number table) for one chunk.
function Mesher.buildChunk(map, chunk)
  local verts, nv = {}, 0
  local palette = map.palette
  local get = map.get
  local solid = {}
  for i, d in ipairs(palette) do solid[i] = d.solid ~= false end
  local function opaque(x, y, z)
    local id = get(map, x, y, z)
    return id ~= 0 and solid[id] ~= false
  end

  local ox, oy, oz = chunk.cx * CS, chunk.cy * CS, chunk.cz * CS
  local ao = { 0, 0, 0, 0 }

  for idx, id in pairs(chunk.data) do
    local x = ox + idx % CS
    local y = oy + floor(idx / CS) % CS
    local z = oz + floor(idx / CS2)
    local def = palette[id] or { color = { 1, 0, 1 }, solid = true }
    local cr, cg, cb = def.color[1], def.color[2], def.color[3]
    local alpha = def.alpha or 1
    local u0, v0, u1, v1 = 0, 0, 1, 1
    if def.uv then u0, v0, u1, v1 = def.uv[1], def.uv[2], def.uv[3], def.uv[4] end

    for fi = 1, 6 do
      local f = FACES[fi]
      local n, tu, tv = f.n, f.u, f.v
      local nid = get(map, x + n[1], y + n[2], z + n[3])
      -- draw the face when it borders air, or a see-through block of another kind
      if nid == 0 or (nid ~= id and solid[nid] == false) then
        local bx = x + (n[1] > 0 and 1 or 0)
        local by = y + (n[2] > 0 and 1 or 0)
        local bz = z + (n[3] > 0 and 1 or 0)
        for ci = 1, 4 do
          local a, b = CORNERS[ci][1], CORNERS[ci][2]
          local su, sv = a * 2 - 1, b * 2 - 1
          -- cell layer in front of the face, then the three AO neighbours
          local px, py, pz = x + n[1], y + n[2], z + n[3]
          local s1 = opaque(px + tu[1] * su, py + tu[2] * su, pz + tu[3] * su)
          local s2 = opaque(px + tv[1] * sv, py + tv[2] * sv, pz + tv[3] * sv)
          local c = opaque(px + tu[1] * su + tv[1] * sv, py + tu[2] * su + tv[2] * sv,
                           pz + tu[3] * su + tv[3] * sv)
          local free
          if s1 and s2 then free = 0 else free = 3 - ((s1 and 1 or 0) + (s2 and 1 or 0) + (c and 1 or 0)) end
          ao[ci] = free
        end
        -- flip the quad diagonal to avoid the classic AO anisotropy artefact
        local order
        if ao[1] + ao[3] > ao[2] + ao[4] then
          order = f.flip and { 2, 4, 3, 2, 1, 4 } or { 2, 3, 4, 2, 4, 1 }
        else
          order = f.flip and { 1, 3, 2, 1, 4, 3 } or { 1, 2, 3, 1, 3, 4 }
        end
        for k = 1, 6 do
          local ci = order[k]
          local a, b = CORNERS[ci][1], CORNERS[ci][2]
          local sh = f.shade * AO[ao[ci]]
          nv = nv + 1
          verts[nv] = {
            bx + tu[1] * a + tv[1] * b,
            by + tu[2] * a + tv[2] * b,
            bz + tu[3] * a + tv[3] * b,
            u0 + a * (u1 - u0), v0 + (1 - b) * (v1 - v0),
            n[1], n[2], n[3],
            cr * sh, cg * sh, cb * sh, alpha,
          }
        end
      end
    end
  end
  return verts
end

-- Vertices of a flat-coloured cube spanning x,y in [0,1] (or [-.5,.5] when
-- `centered`) and z in [0,1]. Used for the editor's cursor / entity boxes.
function Mesher.cubeVerts(r, g, b, a, centered)
  local verts, off = {}, centered and 0.5 or 0
  for _, f in ipairs(FACES) do
    local n, tu, tv = f.n, f.u, f.v
    local bx, by, bz = n[1] > 0 and 1 or 0, n[2] > 0 and 1 or 0, n[3] > 0 and 1 or 0
    for _, ci in ipairs(f.flip and { 1, 3, 2, 1, 4, 3 } or { 1, 2, 3, 1, 3, 4 }) do
      local ca, cb = CORNERS[ci][1], CORNERS[ci][2]
      local sh = f.shade
      verts[#verts + 1] = {
        bx + tu[1] * ca + tv[1] * cb - off,
        by + tu[2] * ca + tv[2] * cb - off,
        bz + tu[3] * ca + tv[3] * cb,
        0, 0, n[1], n[2], n[3], r * sh, g * sh, b * sh, a,
      }
    end
  end
  return verts
end

-- 1x1 white texture so untextured (vertex-colour only) models work with g3d's shader
function Mesher.whiteTexture()
  local data = love.image.newImageData(1, 1)
  data:setPixel(0, 0, 1, 1, 1, 1)
  local img = love.graphics.newImage(data)
  img:setFilter("nearest", "nearest")
  return img
end

-- Rebuild models for every dirty chunk. `models` is a ckey -> g3d model table
-- owned by the caller. Returns the number of chunks rebuilt.
function Mesher.update(map, models, g3d, texture, budget)
  local n = 0
  for k, d in pairs(map.dirty) do
    local chunk = map.chunks[k]
    local verts = chunk and Mesher.buildChunk(map, chunk)
    if verts and #verts > 0 then
      models[k] = g3d.newModel(verts, texture)
    else
      models[k] = nil
    end
    map.dirty[k] = nil
    n = n + 1
    if budget and n >= budget then break end
  end
  return n
end

-- Convenience for games: mesh the whole map at once, returns ckey -> model.
function Mesher.buildAll(map, g3d, texture)
  local models = {}
  for k, c in pairs(map.chunks) do map.dirty[k] = { c.cx, c.cy, c.cz } end
  Mesher.update(map, models, g3d, texture)
  return models
end

return Mesher
