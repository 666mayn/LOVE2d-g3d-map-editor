-- Entity type definitions. Pass your own list to Editor.new{ entityTypes = ... }
-- (same shape) to describe your game's objects.
--
--   name       string, stored in the map file as entity.type
--   color      {r,g,b} used for the editor box
--   size       {w, d, h}  extent in x, y, z  (x,y centred on the entity, z = bottom)
--   sizeProps  optional {"w","d","h"}: read the size from these props instead
--   group      optional heading the entity panel files this type under
--   unique     optional: only one allowed per map (placing again moves it)
--   props      list of {name=, kind="number"|"string"|"bool"|"choice", default=, options=}
local Entities = {}

Entities.defaults = {
  { name = "player_start", color = { 0.25, 0.9, 0.35 }, size = { 0.6, 0.6, 1.8 }, unique = true, props = {} },
  { name = "light", color = { 1.0, 0.88, 0.3 }, size = { 0.35, 0.35, 0.35 },
    props = {
      { name = "color", kind = "string", default = "#ffffff" },
      { name = "intensity", kind = "number", default = 1 },
      { name = "radius", kind = "number", default = 8 },
    } },
  { name = "enemy_spawn", color = { 0.95, 0.3, 0.3 }, size = { 0.8, 0.8, 1.6 },
    props = {
      { name = "enemy", kind = "string", default = "grunt" },
      { name = "count", kind = "number", default = 1 },
    } },
  { name = "pickup", color = { 0.3, 0.7, 1.0 }, size = { 0.5, 0.5, 0.5 },
    props = {
      { name = "item", kind = "string", default = "coin" },
      { name = "amount", kind = "number", default = 1 },
    } },
  { name = "trigger", color = { 0.85, 0.45, 1.0 }, sizeProps = { "w", "d", "h" }, size = { 2, 2, 2 },
    props = {
      { name = "w", kind = "number", default = 2 },
      { name = "d", kind = "number", default = 2 },
      { name = "h", kind = "number", default = 2 },
      { name = "target", kind = "string", default = "" },
      { name = "once", kind = "bool", default = false },
    } },
  --   waypoint    one stop on a path. Any entity with a `route` prop (give your own entity types one) follows the
  --               waypoints whose `route` is the same, in `order` (1, 2, 3 ...), then loops. Same order = placement
  --               order. The editor draws each route as coloured lines (see routes.lua).
  { name = "waypoint", group = "Paths", color = { 0.25, 0.85, 0.95 }, size = { 0.5, 0.5, 0.5 },
    props = {
      { name = "route", kind = "string", default = "" },
      { name = "order", kind = "number", default = 1 },
    } },
  { name = "prop", color = { 0.8, 0.8, 0.8 }, size = { 1, 1, 1 },
    props = {
      { name = "model", kind = "string", default = "" },
      { name = "scale", kind = "number", default = 1 },
    } },
}

function Entities.index(list)
  local by = {}
  for _, t in ipairs(list) do by[t.name] = t end
  return by
end

-- fresh props table for a new entity of this type
function Entities.newProps(def)
  local p = {}
  for _, pd in ipairs(def.props or {}) do p[pd.name] = pd.default end
  return p
end

-- Entity extent w, d, h
function Entities.size(def, e)
  def = def or {}
  local s = def.size or { 1, 1, 1 }
  local w, d, h = s[1], s[2], s[3]
  if def.sizeProps and e and e.props then
    w = tonumber(e.props[def.sizeProps[1]]) or w
    d = tonumber(e.props[def.sizeProps[2]]) or d
    h = tonumber(e.props[def.sizeProps[3]]) or h
  end
  -- keep boxes pickable / drawable even if someone types 0
  return math.max(w, 0.1), math.max(d, 0.1), math.max(h, 0.1)
end

return Entities
