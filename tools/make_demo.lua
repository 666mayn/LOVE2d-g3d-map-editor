-- Regenerates map_editor/maps/demo.lua. From the project root:  lua tools/make_demo.lua
-- Also a small example of building a map from code.
package.path = "./?.lua;./?/init.lua;" .. package.path
local Map = require("map_editor.map")

local GRASS, DIRT, STONE, COBBLE, SAND, BRICK, WOOD, PLANK, SNOW, ICE, LAVA, WATER =
  1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12

local m = Map.new({ name = "demo" })
m.sky = { 0.52, 0.72, 0.93 }

-- ground: grass over two layers of dirt
m:fillBox(0, 0, -2, 31, 31, -1, DIRT)
m:fillBox(0, 0, 0, 31, 31, 0, GRASS)

-- pond with a sand rim
m:fillBox(19, 3, 0, 28, 11, 0, SAND)
m:fillBox(20, 4, -1, 27, 10, 0, WATER)
m:fillBox(20, 4, -2, 27, 10, -2, SAND)

-- hill (stepped pyramid, stone core, grass skin)
for k = 1, 4 do
  m:fillBox(4 + k, 18 + k, k, 14 - k, 28 - k, k, STONE)
end
for k = 1, 4 do
  m:fillBox(4 + k, 18 + k, k, 14 - k, 28 - k, k, STONE)
  for x = 4 + k, 14 - k do
    for y = 18 + k, 28 - k do
      if x == 4 + k or x == 14 - k or y == 18 + k or y == 28 - k or k == 4 then m:set(x, y, k, GRASS) end
    end
  end
end
m:fillBox(8, 22, 4, 10, 24, 4, SNOW)

-- house
m:fillBox(12, 8, 0, 19, 14, 0, PLANK)             -- floor
for z = 1, 3 do
  m:fillBox(12, 8, z, 19, 8, z, BRICK)            -- walls
  m:fillBox(12, 14, z, 19, 14, z, BRICK)
  m:fillBox(12, 8, z, 12, 14, z, BRICK)
  m:fillBox(19, 8, z, 19, 14, z, BRICK)
end
m:fillBox(15, 8, 1, 16, 8, 2, 0)                  -- doorway
m:set(13, 8, 2, 0); m:set(18, 8, 2, 0)            -- windows
m:set(12, 11, 2, 0); m:set(19, 11, 2, 0)
m:fillBox(11, 7, 4, 20, 15, 4, PLANK)             -- roof with overhang
m:fillBox(12, 8, 5, 19, 14, 5, WOOD)
m:fillBox(13, 9, 6, 18, 13, 6, WOOD)

-- stairs up to a ledge
for i = 0, 3 do m:fillBox(2, 14 + i, 1, 4, 14 + i, 1 + i, COBBLE) end
m:fillBox(2, 18, 1, 4, 20, 4, COBBLE)

-- plaza pillars
for _, p in ipairs({ { 8, 3 }, { 8, 7 }, { 12, 3 }, { 12, 7 } }) do
  m:fillBox(p[1], p[2], 1, p[1], p[2], 3, COBBLE)
  m:set(p[1], p[2], 4, STONE)
end

-- lava pit with a cobble rim
m:fillBox(1, 1, 0, 5, 5, 0, COBBLE)
m:fillBox(2, 2, 0, 4, 4, 0, LAVA)

-- an ice bridge across the pond
m:fillBox(19, 7, 0, 28, 7, 0, ICE)

local function entity(type_, x, y, z, yaw, props, name)
  m:addEntity({ type = type_, x = x, y = y, z = z, yaw = yaw or 0, props = props or {}, name = name or "" })
end

entity("player_start", 15.5, 4.5, 1, 90)
entity("light", 15.5, 11.5, 2.5, 0, { color = "#ffcc88", intensity = 1.2, radius = 7 }, "hearth")
entity("light", 8.5, 3.5, 4.5, 0, { color = "#ff9955", intensity = 1, radius = 6 }, "torch1")
entity("light", 12.5, 7.5, 4.5, 0, { color = "#ff9955", intensity = 1, radius = 6 }, "torch2")
entity("pickup", 9.5, 23.5, 5, 0, { item = "crystal", amount = 1 })
entity("pickup", 3.5, 19.5, 5, 0, { item = "coin", amount = 10 })
entity("enemy_spawn", 26.5, 26.5, 1, 225, { enemy = "grunt", count = 3 })
entity("trigger", 15.5, 8.5, 1, 0, { w = 2, d = 1.5, h = 3, target = "enter_house", once = true }, "door_trigger")
entity("prop", 24.5, 14.5, 1, 45, { model = "tree", scale = 1.5 })

local ok, where = m:save("map_editor/maps/demo.lua")
assert(ok, where)
print(("wrote %s: %d blocks, %d entities"):format(where, m.count, #m.entities))
