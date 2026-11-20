-- Surface types: an optional tag on a block type ("what this block IS"), shown in the editor as a colour,
-- so a map can be built and read at a glance with zero art. Your game decides what each tag means (e.g. which
-- material or texture to apply when it meshes the map). The tag is saved in the map file as palette[i].surface.
--
--   id     stored in the map file as palette[i].surface
--   label  shown in the editor
--   color  editor colour for blocks of this type
--
-- Use your own list at start-up (before the editor opens):
--   require("map_editor").Surfaces.setTypes{
--     { id = "brick", label = "Brick", color = { 0.7, 0.3, 0.25 } },
--     { id = "glass", label = "Glass", color = { 0.6, 0.8, 0.9 } },
--   }
local Surfaces = {}

Surfaces.defaults = {
  { id = "wall",     label = "Wall",     color = { 0.72, 0.33, 0.27 } },   -- brick red
  { id = "concrete", label = "Concrete", color = { 0.55, 0.55, 0.58 } },   -- grey
  { id = "ground",   label = "Ground",   color = { 0.30, 0.66, 0.30 } },   -- green
  { id = "floor",    label = "Floor",    color = { 0.93, 0.82, 0.28 } },   -- yellow
  { id = "ceiling",  label = "Ceiling",  color = { 0.58, 0.80, 0.93 } },   -- light blue
}

Surfaces.types = {}
Surfaces.byId = {}

-- Replace the list of surface types (also rebuilds the lookup tables).
function Surfaces.setTypes(list)
  Surfaces.types, Surfaces.byId = {}, {}
  for i, t in ipairs(list or Surfaces.defaults) do
    local copy = { id = t.id, label = t.label or t.id, color = { t.color[1], t.color[2], t.color[3] }, index = i }
    Surfaces.types[i] = copy
    Surfaces.byId[copy.id] = copy
  end
end

Surfaces.setTypes(Surfaces.defaults)

-- A fresh palette: one solid block type per surface type, coloured by type.
function Surfaces.palette()
  local p = {}
  for i, t in ipairs(Surfaces.types) do
    p[i] = { name = t.label, surface = t.id, color = { t.color[1], t.color[2], t.color[3] }, solid = true }
  end
  return p
end

-- palette index whose surface is `id` (nil when the palette has none)
function Surfaces.find(palette, id)
  for i, d in ipairs(palette) do if d.surface == id then return i end end
end

return Surfaces
